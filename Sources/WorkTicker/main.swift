import AppKit
import SwiftUI

// MARK: - Config

struct Config: Codable {
    var monthlySalarySGD: Double
    var workStart: String
    var workEnd: String
    var lunchStart: String
    var lunchEnd: String
    var payDay: Int

    static let `default` = Config(
        monthlySalarySGD: 5000, workStart: "10:00", workEnd: "18:30", lunchStart: "12:00", lunchEnd: "13:30",
        payDay: 30)
}

struct ConfigError: LocalizedError {
    let errorDescription: String?
}

let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/work-ticker")
let configURL = configDir.appendingPathComponent("config.json")
let rateURL = configDir.appendingPathComponent("rate.json")

func saveConfig(_ cfg: Config) throws {
    try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(cfg).write(to: configURL)
}

func loadConfig() throws -> Config {
    if !FileManager.default.fileExists(atPath: configURL.path) {
        try saveConfig(.default)
        return .default
    }
    return try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
}

func secondsOfDay(_ s: String) throws -> Double {
    let p = s.split(separator: ":").compactMap { Int($0) }
    guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else {
        throw ConfigError(errorDescription: "时间格式应为 HH:mm，收到 \"\(s)\"")
    }
    return Double(p[0] * 3600 + p[1] * 60)
}

// MARK: - Salary math

struct Snapshot {
    let status: String
    let worked: Double
    let toOff: Double
    let progress: Double
    let perSecond: Double
    let today: Double
    let cycle: Double
    let daysToPay: Int
}

struct Salary {
    let start, end, lunchStart, lunchEnd: Double
    let monthly: Double
    let payDay: Int
    let workSeconds: Double

    init(_ cfg: Config) throws {
        start = try secondsOfDay(cfg.workStart)
        end = try secondsOfDay(cfg.workEnd)
        lunchStart = try secondsOfDay(cfg.lunchStart)
        lunchEnd = try secondsOfDay(cfg.lunchEnd)
        guard start < lunchStart, lunchStart <= lunchEnd, lunchEnd < end else {
            throw ConfigError(errorDescription: "需满足 上班 < 午休开始 <= 午休结束 < 下班")
        }
        guard cfg.monthlySalarySGD > 0 else { throw ConfigError(errorDescription: "月薪需大于 0") }
        guard (1...31).contains(cfg.payDay) else { throw ConfigError(errorDescription: "发薪日需在 1 到 31 之间") }
        monthly = cfg.monthlySalarySGD
        payDay = cfg.payDay
        workSeconds = (end - start) - (lunchEnd - lunchStart)
    }

    // Shown on the card only: a 20-day month of 8-hour days.
    var displayDaily: Double { monthly / 20 }
    var displayHourly: Double { monthly / 20 / 8 }

    /// Pay date in the month containing `date`; months shorter than `payDay` pay on their last day.
    func payDate(inMonthOf date: Date, _ cal: Calendar) -> Date {
        let first = cal.date(from: cal.dateComponents([.year, .month], from: date))!
        let length = cal.range(of: .day, in: .month, for: first)!.count
        return cal.date(byAdding: .day, value: min(payDay, length) - 1, to: first)!
    }

    func snapshot(at now: Date, cal: Calendar = .current) -> Snapshot {
        let todayStart = cal.startOfDay(for: now)
        let t = now.timeIntervalSince(todayStart)
        let workday = !cal.isDateInWeekend(now)
        let worked = workday ? max(0, min(t, lunchStart) - start) + max(0, min(t, end) - lunchEnd) : 0

        let status: String
        if !workday { status = "休息日" }
        else if t < start { status = "未上班" }
        else if t < lunchStart { status = "在岗" }
        else if t < lunchEnd { status = "午休" }
        else if t < end { status = "在岗" }
        else { status = "已下班" }

        // Pay cycle: the day after the previous pay date through the next pay date (inclusive).
        var cycleEnd = payDate(inMonthOf: now, cal)
        if todayStart > cycleEnd {
            cycleEnd = payDate(inMonthOf: cal.date(byAdding: .month, value: 1, to: now)!, cal)
        }
        let previousPay = payDate(inMonthOf: cal.date(byAdding: .month, value: -1, to: cycleEnd)!, cal)
        var total = 0, before = 0
        var day = cal.date(byAdding: .day, value: 1, to: previousPay)!
        while day <= cycleEnd {
            if !cal.isDateInWeekend(day) {
                total += 1
                if day < todayStart { before += 1 }
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }

        let daily = monthly / Double(total)
        let perSecond = daily / workSeconds
        let today = perSecond * worked
        return Snapshot(
            status: status,
            worked: worked,
            toOff: workday ? max(0, end - t) : 0,
            progress: worked / workSeconds,
            perSecond: perSecond,
            today: today,
            cycle: Double(before) * daily + today,
            daysToPay: cal.dateComponents([.day], from: todayStart, to: cycleEnd).day!)
    }
}

@MainActor
final class SalaryStore: ObservableObject {
    @Published private(set) var salary: Salary
    private(set) var config: Config

    init(_ config: Config) throws {
        salary = try Salary(config)
        self.config = config
    }

    func update(_ new: Config) throws {
        let validated = try Salary(new)
        try saveConfig(new)
        config = new
        salary = validated
    }
}

// MARK: - Exchange rate

struct RateCache: Codable {
    var cny: Double
    var updated: Date
}

@MainActor
final class RateStore: ObservableObject {
    @Published var cache: RateCache?
    private var timer: Timer?

    init() {
        if let data = try? Data(contentsOf: rateURL) {
            cache = try? JSONDecoder().decode(RateCache.self, from: data)
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task {
            struct Resp: Decodable {
                let result: String
                let time_last_update_unix: Double
                let rates: [String: Double]
            }
            do {
                let url = URL(string: "https://open.er-api.com/v6/latest/SGD")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let r = try JSONDecoder().decode(Resp.self, from: data)
                guard r.result == "success", let cny = r.rates["CNY"] else {
                    throw ConfigError(errorDescription: "接口返回 \(r.result)，无 CNY")
                }
                let c = RateCache(cny: cny, updated: Date(timeIntervalSince1970: r.time_last_update_unix))
                cache = c
                try JSONEncoder().encode(c).write(to: rateURL)
            } catch {
                FileHandle.standardError.write("汇率更新失败: \(error)\n".data(using: .utf8)!)
            }
        }
    }
}

// MARK: - View

let green = Color(red: 0.24, green: 0.86, blue: 0.40)

func hms(_ t: Double) -> String {
    let s = Int(t)
    return String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
}

func message(_ s: Snapshot) -> String {
    switch s.status {
    case "休息日": return "今天休息，别想工作"
    case "未上班": return "还没开工，先吃早饭"
    case "午休": return "午休中，好好吃饭"
    case "已下班": return "下班了，今天的钱已到手"
    default:
        if s.progress < 0.25 { return "刚开工，慢慢进入状态" }
        if s.progress < 0.5 { return "稳住，钱在一秒一秒进账" }
        if s.progress < 0.75 { return "过半了，喝口水" }
        return "收尾阶段，别硬熬"
    }
}

let panelBackground = Color(red: 0.11, green: 0.13, blue: 0.15).opacity(0.95)

func formatMoney(_ sgd: Double, _ digits: Int, cny: Bool, rate: Double?) -> String {
    let sym = cny ? "¥" : "S$"
    let value = cny ? rate.map { sgd * $0 } : sgd
    guard let value else { return sym + "--" }
    return sym + value.formatted(.number.precision(.fractionLength(digits)).rounded(rule: .toNearestOrAwayFromZero))
}

struct CardView: View {
    @ObservedObject var store: SalaryStore
    @ObservedObject var rates: RateStore
    let onMinimize: () -> Void
    let onSettings: () -> Void
    @AppStorage("useCNY") private var useCNY = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            content(store.salary.snapshot(at: ctx.date))
        }
        .padding(16)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 14).fill(panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08)))
        .environment(\.colorScheme, .dark)
        .gesture(WindowDragGesture())
        .contextMenu {
            Button(useCNY ? "显示新币" : "显示人民币") { useCNY.toggle() }
            Button("设置…", action: onSettings)
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
    }

    func money(_ sgd: Double, _ digits: Int) -> String {
        formatMoney(sgd, digits, cny: useCNY, rate: rates.cache?.cny)
    }

    func content(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日已赚").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                badge(s.status)
                Button(action: onMinimize) {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            Text(money(s.today, 3))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(green)
                .contentShape(Rectangle())
                .onTapGesture { useCNY.toggle() }
            HStack(alignment: .top) {
                stat("每秒进账", money(s.perSecond, 4))
                stat("时薪", money(store.salary.displayHourly, 0))
                stat("日薪", money(store.salary.displayDaily, 0))
            }
            Divider()
            HStack {
                Text("已工作 \(hms(s.worked))")
                Spacer()
                Text("\(Int(s.progress * 100))%")
                Spacer()
                Text("距下班 \(hms(s.toOff))").foregroundStyle(green)
            }
            .font(.system(size: 12))
            .monospacedDigit()
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [green, .yellow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * min(1, s.progress))
                }
            }
            .frame(height: 6)
            HStack {
                Text("本期已赚 \(money(s.cycle, 2))")
                Spacer()
                Text(s.daysToPay == 0 ? "今天发工资" : "距发工资 \(s.daysToPay) 天")
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            Text(message(s))
                .font(.system(size: 13))
                .frame(maxWidth: .infinity)
            Text(rateLine)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
    }

    var rateLine: String {
        guard let c = rates.cache else { return "汇率未获取" }
        return "1 SGD = \(c.cny.formatted(.number.precision(.fractionLength(4)))) CNY · "
            + c.updated.formatted(.dateTime.month(.twoDigits).day(.twoDigits)) + " 更新"
    }

    func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func badge(_ status: String) -> some View {
        let color: Color = switch status {
        case "在岗": green
        case "午休": .orange
        default: .gray
        }
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(status).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.18)))
    }
}

// MARK: - Settings

func timeOfDay(_ s: String) -> Date {
    Calendar.current.startOfDay(for: Date()).addingTimeInterval((try? secondsOfDay(s)) ?? 0)
}

func hhmm(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
    return String(format: "%02d:%02d", c.hour!, c.minute!)
}

struct SettingsView: View {
    @State private var salary: Double
    @State private var workStart: Date
    @State private var workEnd: Date
    @State private var lunchStart: Date
    @State private var lunchEnd: Date
    @State private var payDay: Int
    @State private var error: String?
    let onSave: (Config) throws -> Void

    init(config: Config, onSave: @escaping (Config) throws -> Void) {
        _salary = State(initialValue: config.monthlySalarySGD)
        _workStart = State(initialValue: timeOfDay(config.workStart))
        _workEnd = State(initialValue: timeOfDay(config.workEnd))
        _lunchStart = State(initialValue: timeOfDay(config.lunchStart))
        _lunchEnd = State(initialValue: timeOfDay(config.lunchEnd))
        _payDay = State(initialValue: config.payDay)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 16) {
            Form {
                TextField("月薪（新币）", value: $salary, format: .number)
                DatePicker("上班", selection: $workStart, displayedComponents: .hourAndMinute)
                DatePicker("下班", selection: $workEnd, displayedComponents: .hourAndMinute)
                DatePicker("午休开始", selection: $lunchStart, displayedComponents: .hourAndMinute)
                DatePicker("午休结束", selection: $lunchEnd, displayedComponents: .hourAndMinute)
                Picker("发薪日", selection: $payDay) {
                    ForEach(1...31, id: \.self) { Text("每月 \($0) 号") }
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("保存", action: save).keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 320)
    }

    func save() {
        let cfg = Config(
            monthlySalarySGD: salary, workStart: hhmm(workStart), workEnd: hhmm(workEnd),
            lunchStart: hhmm(lunchStart), lunchEnd: hhmm(lunchEnd), payDay: payDay)
        do {
            try onSave(cfg)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel?
    var rates: RateStore?
    var store: SalaryStore?
    var statusItem: NSStatusItem?
    var ticker: Timer?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store: SalaryStore
        do {
            store = try SalaryStore(loadConfig())
        } catch {
            let alert = NSAlert()
            alert.messageText = "配置文件有误"
            alert.informativeText = "\(configURL.path)\n\(error.localizedDescription)"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        // Hidden menu so text-editing shortcuts work in the settings window.
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(editItem)

        self.store = store
        let rates = RateStore()
        self.rates = rates
        let host = NSHostingView(rootView: CardView(
            store: store, rates: rates,
            onMinimize: { [weak self] in self?.panel?.orderOut(nil) },
            onSettings: { [weak self] in self?.openSettings() }))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        if !panel.setFrameUsingName("WorkTicker"), let vf = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: vf.maxX - panel.frame.width - 20, y: vf.minY + 20))
        }
        panel.setFrameAutosaveName("WorkTicker")
        panel.orderFrontRegardless()
        self.panel = panel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusTitle()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusTitle() }
        }
    }

    func updateStatusTitle() {
        guard let store, let button = statusItem?.button else { return }
        let today = store.salary.snapshot(at: Date()).today
        button.title = formatMoney(
            today, 2, cny: UserDefaults.standard.bool(forKey: "useCNY"), rate: rates?.cache?.cny)
    }

    @objc func statusItemClicked() {
        guard let panel, let item = statusItem else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let useCNY = UserDefaults.standard.bool(forKey: "useCNY")
            let menu = NSMenu()
            menu.addItem(withTitle: useCNY ? "显示新币" : "显示人民币", action: #selector(toggleCurrency), keyEquivalent: "")
                .target = self
            menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc func toggleCurrency() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "useCNY"), forKey: "useCNY")
        updateStatusTitle()
    }

    @objc func openSettings() {
        guard let store else { return }
        if settingsWindow?.isVisible != true {
            let view = SettingsView(config: store.config) { [weak self] cfg in
                try self?.store?.update(cfg)
                self?.updateStatusTitle()
                self?.settingsWindow?.close()
            }
            let controller = NSHostingController(rootView: view)
            controller.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "设置"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
