import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var draft: Config
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
        VStack(spacing: 0) {
            if firstRun {
                Text(L("欢迎使用薪跳，先填一下工资和上下班时间")).padding(.top, 16)
            }
            TabView {
                salaryTab.tabItem { Text(L("薪资")) }
                timeTab.tabItem { Text(L("时间")) }
                lookTab.tabItem { Text(L("外观")) }
                messagesTab.tabItem { Text(L("鼓励语")) }
                generalTab.tabItem { Text(L("通用")) }
            }
            .padding(16)
            Divider()
            HStack(alignment: .firstTextBaseline) {
                summary
                Spacer()
                Button(firstRun ? L("开始使用") : L("保存"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled((try? preview.get()) == nil)
            }
            .padding(16)
        }
        .frame(width: 500)
        .onChange(of: draft) { _, new in
            saveError = nil
            holidays.load(new.holidayRegion)
            onChange(new)
        }
    }

    @ViewBuilder var summary: some View {
        switch preview {
        case .success(let s):
            let m = { (v: Double, d: Int) in formatMoney(v, draft.currency, d) }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("本期 %d 个工作日 · 日薪 %@ · 时薪 %@", s.cycleWorkdays, m(s.daily, 2), m(s.hourly, 2)))
                Text(L("每秒进账 %@", m(s.perSecond, 4)))
                if let saveError { Text(saveError).foregroundStyle(.red) }
            }
            .font(.callout)
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

    // MARK: Tabs

    var salaryTab: some View {
        Form {
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
            Picker(L("工资币种"), selection: $draft.currency) {
                ForEach(commonCurrencies, id: \.self) { Text(verbatim: "\(currencyName($0)) \($0)").tag($0) }
            }
            Picker(L("换算币种"), selection: $draft.altCurrency) {
                Text(L("不换算")).tag("")
                ForEach(commonCurrencies.filter { $0 != draft.currency }, id: \.self) {
                    Text(verbatim: "\(currencyName($0)) \($0)").tag($0)
                }
            }
            Picker(L("发薪日"), selection: $draft.payDay) {
                ForEach(1...31, id: \.self) { Text(L("每月 %d 号", $0)).tag($0) }
            }
            Toggle(L("发薪日遇到休息日提前发"), isOn: $draft.payEarlyOnHoliday)
        }
    }

    var timeTab: some View {
        Form {
            DatePicker(L("上班"), selection: time(\.workStart), displayedComponents: .hourAndMinute)
            DatePicker(L("下班"), selection: time(\.workEnd), displayedComponents: .hourAndMinute)
            Toggle(L("有午休"), isOn: $draft.hasLunch)
            if draft.hasLunch {
                DatePicker(L("午休开始"), selection: time(\.lunchStart), displayedComponents: .hourAndMinute)
                DatePicker(L("午休结束"), selection: time(\.lunchEnd), displayedComponents: .hourAndMinute)
            }
            LabeledContent(L("工作日")) {
                HStack(spacing: 4) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                        Toggle(Calendar.current.shortWeekdaySymbols[weekday - 1], isOn: workday(weekday))
                            .toggleStyle(.button)
                    }
                }
            }
            Picker(L("节假日"), selection: $draft.holidayRegion) {
                Text(regionName("")).tag("")
                Text(regionName("CN")).tag("CN")
                Divider()
                ForEach(holidayRegions.dropFirst().sorted { regionName($0) < regionName($1) }, id: \.self) {
                    Text(regionName($0)).tag($0)
                }
            }
            Toggle(L("下班后继续计时（加班）"), isOn: $draft.overtime)
            if draft.overtime {
                TextField(L("加班倍率"), value: $draft.overtimeRate, format: .number)
            }
        }
    }

    var lookTab: some View {
        Form {
            LabeledContent(L("主题色")) {
                HStack(spacing: 8) {
                    ForEach(accentColors, id: \.hex) { c in
                        Circle()
                            .fill(Color(hex: c.hex))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary, lineWidth: draft.accent == c.hex ? 2 : 0).padding(-3))
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
            Picker(L("今日已赚小数位"), selection: $draft.todayDecimals) {
                ForEach(0...4, id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
            LabeledContent(L("卡片显示")) {
                VStack(alignment: .leading) {
                    Toggle(L("每秒进账、时薪、日薪"), isOn: $draft.showRates)
                    Toggle(L("工作进度"), isOn: $draft.showProgress)
                    Toggle(L("本期已赚和发薪倒计时"), isOn: $draft.showCycle)
                    Toggle(L("鼓励语"), isOn: $draft.showMessage)
                    Toggle(L("汇率"), isOn: $draft.showRateLine)
                }
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
            Picker(L("菜单栏显示"), selection: $draft.statusBar) {
                ForEach(StatusBarMode.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    var messagesTab: some View {
        Form {
            ForEach(MessageSlot.allCases) { slot in
                TextField(slot.label, text: message(slot), prompt: Text(slot.defaultText))
            }
        }
    }

    var generalTab: some View {
        Form {
            Toggle(L("开机自启"), isOn: $launchAtLogin)
            Toggle(L("自动检查更新"), isOn: $draft.checkUpdates)
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
