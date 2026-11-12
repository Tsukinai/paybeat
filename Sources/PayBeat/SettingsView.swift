import ServiceManagement
import SwiftUI

enum SettingsPage: String, Identifiable, Hashable {
    case salary, time, display, look, messages, general
    var id: String { rawValue }

    var title: String {
        switch self {
        case .salary: L("薪资")
        case .time: L("时间")
        case .display: L("显示")
        case .look: L("外观")
        case .messages: L("鼓励语")
        case .general: L("通用")
        }
    }

    var icon: String {
        switch self {
        case .salary: "banknote.fill"
        case .time: "clock.fill"
        case .display: "macbook"
        case .look: "paintbrush.fill"
        case .messages: "text.bubble.fill"
        case .general: "gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .salary: .green
        case .time: .orange
        case .display: .teal
        case .look: .blue
        case .messages: .pink
        case .general: .gray
        }
    }
}

/// Sidebar entry in the System Settings style: a white glyph on a rounded colored square.
private struct SidebarRow: View {
    let page: SettingsPage

    var body: some View {
        Label {
            Text(page.title)
                .font(.system(size: 13))
                .padding(.leading, 2)
        } icon: {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(page.color.gradient)
                    .frame(width: 24, height: 24)
                Image(systemName: page.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}

struct SettingsView: View {
    @State private var draft: Config
    @State private var page = SettingsPage.salary
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var saveError: String?
    @ObservedObject var holidays: HolidayStore
    @ObservedObject var updates: UpdateChecker
    let firstRun: Bool
    let onChange: (Config) -> Void
    let onSave: (Config, Bool) throws -> Void

    init(
        config: Config, holidays: HolidayStore, updates: UpdateChecker, firstRun: Bool,
        onChange: @escaping (Config) -> Void, onSave: @escaping (Config, Bool) throws -> Void
    ) {
        _draft = State(initialValue: config)
        self.holidays = holidays
        self.updates = updates
        self.firstRun = firstRun
        self.onChange = onChange
        self.onSave = onSave
    }

    private var preview: Result<Snapshot, Error> {
        Result {
            try Salary(draft).snapshot(
                at: Date(), holidays: holidays.calendar(for: draft.holidayRegion), overtimeEnd: nil)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Section {
                    ForEach([SettingsPage.salary, .time, .display, .look, .messages]) { p in
                        SidebarRow(page: p).tag(p)
                    }
                }
                Section(L("薪跳")) {
                    SidebarRow(page: .general).tag(SettingsPage.general)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            detail
                .formStyle(.grouped)
                .navigationTitle(page.title)
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 680, minHeight: 500)
        .onChange(of: draft) { _, new in
            saveError = nil
            holidays.load(new.holidayRegion)
            onChange(new)
        }
    }

    @ViewBuilder var detail: some View {
        switch page {
        case .salary: salaryPage
        case .time: timePage
        case .display: displayPage
        case .look: lookPage
        case .messages: messagesPage
        case .general: generalPage
        }
    }

    var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center, spacing: 12) {
                summary
                Spacer(minLength: 0)
                Button(firstRun ? L("开始使用") : L("保存"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled((try? preview.get()) == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    @ViewBuilder var summary: some View {
        switch preview {
        case .success(let s):
            let m = { (v: Double, d: Int) in formatMoney(v, draft.currency, d) }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("本期 %d 个工作日 · 日薪 %@ · 时薪 %@", s.cycleWorkdays, m(s.daily, 2), m(s.hourly, 2)))
                Text(L("每秒进账 %@ · 每分钟进账 %@", m(s.perSecond, 4), m(s.perSecond * 60, 2)))
                if let saveError { Text(saveError).foregroundStyle(.red) }
            }
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        case .failure(let error):
            Text(saveError ?? error.localizedDescription).font(.callout).foregroundStyle(.red)
        }
    }

    func save() {
        do {
            try onSave(draft, launchAtLogin)
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: Pages

    var salaryPage: some View {
        Form {
            if firstRun {
                Section {
                    Text(L("欢迎使用薪跳，先填一下工资和上下班时间"))
                }
            }
            Section {
                Picker(L("计薪方式"), selection: $draft.salaryType) {
                    ForEach(SalaryType.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField(draft.salaryType.label, value: $draft.salary, format: .number)
                if draft.salaryType == .monthly {
                    Picker(L("每年发"), selection: $draft.monthsPerYear) {
                        ForEach(12...18, id: \.self) { Text(L("%d 薪", $0)).tag($0) }
                    }
                }
            }
            Section {
                Picker(L("工资币种"), selection: $draft.currency) {
                    ForEach(commonCurrencies, id: \.self) { Text(verbatim: "\(currencyName($0)) \($0)").tag($0) }
                }
                Picker(L("换算币种"), selection: $draft.altCurrency) {
                    Text(L("不换算")).tag("")
                    ForEach(commonCurrencies.filter { $0 != draft.currency }, id: \.self) {
                        Text(verbatim: "\(currencyName($0)) \($0)").tag($0)
                    }
                }
            }
            Section {
                Picker(L("发薪日"), selection: $draft.payDay) {
                    ForEach(1...31, id: \.self) { Text(L("每月 %d 号", $0)).tag($0) }
                }
                Toggle(L("发薪日遇到休息日提前发"), isOn: $draft.payEarlyOnHoliday)
            }
        }
    }

    var timePage: some View {
        Form {
            Section {
                DatePicker(L("上班"), selection: time(\.workStart), displayedComponents: .hourAndMinute)
                DatePicker(L("下班"), selection: time(\.workEnd), displayedComponents: .hourAndMinute)
                LabeledContent(L("工作日")) {
                    HStack(spacing: 4) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                            Toggle(Calendar.current.shortWeekdaySymbols[weekday - 1], isOn: workday(weekday))
                                .toggleStyle(.button)
                        }
                    }
                }
            }
            Section {
                Toggle(L("有午休"), isOn: $draft.hasLunch)
                if draft.hasLunch {
                    DatePicker(L("午休开始"), selection: time(\.lunchStart), displayedComponents: .hourAndMinute)
                    DatePicker(L("午休结束"), selection: time(\.lunchEnd), displayedComponents: .hourAndMinute)
                }
            }
            Section {
                Picker(L("节假日"), selection: $draft.holidayRegion) {
                    Text(regionName("")).tag("")
                    Text(regionName("CN")).tag("CN")
                    Divider()
                    ForEach(holidayRegions.dropFirst().sorted { regionName($0) < regionName($1) }, id: \.self) {
                        Text(regionName($0)).tag($0)
                    }
                }
            }
            Section {
                Toggle(L("下班后继续计时（加班）"), isOn: $draft.overtime)
                if draft.overtime {
                    TextField(L("加班倍率"), value: $draft.overtimeRate, format: .number)
                }
            }
        }
    }

    var displayPage: some View {
        Form {
            Section {
                Picker(L("显示方式"), selection: $draft.displayMode) {
                    ForEach(DisplayMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if draft.displayMode == .notch {
                    Picker(L("刘海显示在"), selection: $draft.notchScreen) {
                        Text(L("自动（有刘海的屏幕）")).tag("")
                        ForEach(NSScreen.screens, id: \.self) { screen in
                            if let tag = screenTag(screen) {
                                Text(screenName(screen)).tag(tag)
                            }
                        }
                        // A chosen display that is unplugged keeps its row; the island falls back to auto meanwhile.
                        if !draft.notchScreen.isEmpty,
                           !NSScreen.screens.contains(where: { screenTag($0) == draft.notchScreen }) {
                            Text(L("未连接的显示器")).tag(draft.notchScreen)
                        }
                    }
                }
            }
            Section {
                Picker(L("菜单栏显示"), selection: $draft.statusBar) {
                    ForEach(StatusBarMode.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }

    var lookPage: some View {
        Form {
            Section {
                LabeledContent(L("主题色")) {
                    HStack(spacing: 8) {
                        ForEach(accentColors, id: \.hex) { c in
                            Circle()
                                .fill(Color(hex: c.hex))
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle().stroke(Color.primary, lineWidth: draft.accent == c.hex ? 2 : 0).padding(-3))
                                .onTapGesture { draft.accent = c.hex }
                        }
                    }
                }
                Picker(L("卡片颜色"), selection: $draft.theme) {
                    ForEach(CardTheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Slider(value: $draft.opacity, in: 0.4...1) { Text(L("不透明度")) }
                Slider(value: $draft.scale, in: 0.8...1.4, step: 0.1) { Text(L("卡片大小")) }
            }
            Section(L("卡片显示")) {
                Toggle(L("每秒、每分钟进账，时薪、日薪"), isOn: $draft.showRates)
                Toggle(L("工作进度"), isOn: $draft.showProgress)
                Toggle(L("本期已赚和发薪倒计时"), isOn: $draft.showCycle)
                Toggle(L("鼓励语"), isOn: $draft.showMessage)
                Toggle(L("汇率"), isOn: $draft.showRateLine)
            }
            Section {
                Picker(L("今日已赚小数位"), selection: $draft.todayDecimals) {
                    ForEach(0...4, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }
                if draft.salaryType != .hourly {
                    Picker(L("时薪、日薪算法"), selection: $draft.customBasis) {
                        Text(L("按实际工作时间")).tag(false)
                        Text(L("按固定天数和小时")).tag(true)
                    }
                    if draft.customBasis {
                        TextField(L("每月天数"), value: $draft.basisDays, format: .number)
                        TextField(L("每天小时数"), value: $draft.basisHours, format: .number)
                    }
                }
                Toggle(L("时薪、日薪只显示整数"), isOn: $draft.wholeRates)
            }
        }
    }

    var messagesPage: some View {
        Form {
            Section {
                ForEach(MessageSlot.allCases) { slot in
                    TextField(
                        slot.label, text: message(slot), prompt: Text(slot.defaultTexts.joined(separator: " / ")))
                }
            }
        }
    }

    var generalPage: some View {
        Form {
            Section {
                Toggle(L("开机自启"), isOn: $launchAtLogin)
                Toggle(L("自动检查更新"), isOn: $draft.checkUpdates)
            }
            Section {
                LabeledContent(L("版本")) {
                    HStack {
                        Text(verbatim: appVersion ?? "dev")
                        if let tag = updates.latestTag, let url = updates.latestURL {
                            Link(L("下载新版本 %@", tag), destination: url)
                        }
                    }
                }
                LabeledContent(L("项目主页")) {
                    Link("GitHub" as String, destination: repoURL)
                }
            }
        }
    }

    // MARK: Bindings

    func time(_ key: WritableKeyPath<Config, String>) -> Binding<Date> {
        Binding(get: { timeOfDay(draft[keyPath: key]) }, set: { draft[keyPath: key] = hhmm($0) })
    }

    func workday(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { draft.workdays.contains(weekday) },
            set: { on in
                draft.workdays.removeAll { $0 == weekday }
                if on { draft.workdays.append(weekday) }
                draft.workdays.sort()
            })
    }

    func message(_ slot: MessageSlot) -> Binding<String> {
        Binding(
            get: { draft.messages[slot.rawValue] ?? "" },
            set: { draft.messages[slot.rawValue] = $0.isEmpty ? nil : $0 })
    }
}
