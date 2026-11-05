import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Widget settings (right-click a widget > Edit)

enum CurrencyChoice: String, AppEnum {
    case auto, CNY, USD, SGD, HKD, TWD, MOP, JPY, KRW, EUR, GBP, AUD, CAD, NZD, CHF, MYR, THB, PHP, IDR, VND, INR, AED

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "币种"
    static let caseDisplayRepresentations: [CurrencyChoice: DisplayRepresentation] = [
        .auto: "跟随薪跳设置",
        .CNY: "人民币 CNY", .USD: "美元 USD", .SGD: "新加坡元 SGD", .HKD: "港元 HKD",
        .TWD: "新台币 TWD", .MOP: "澳门元 MOP", .JPY: "日元 JPY", .KRW: "韩元 KRW",
        .EUR: "欧元 EUR", .GBP: "英镑 GBP", .AUD: "澳元 AUD", .CAD: "加元 CAD",
        .NZD: "新西兰元 NZD", .CHF: "瑞士法郎 CHF", .MYR: "马来西亚林吉特 MYR", .THB: "泰铢 THB",
        .PHP: "菲律宾比索 PHP", .IDR: "印尼盾 IDR", .VND: "越南盾 VND", .INR: "印度卢比 INR",
        .AED: "阿联酋迪拉姆 AED",
    ]

    func resolve(_ fallback: String) -> String { self == .auto ? fallback : rawValue }
}

struct EarningsIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "今日已赚"
    static let description = IntentDescription("今天赚了多少、离下班还有多久")

    @Parameter(title: "金额币种", default: .auto)
    var currency: CurrencyChoice

    @Parameter(title: "显示换算金额", default: true)
    var showAlt: Bool

    @Parameter(title: "换算币种", default: .auto)
    var altCurrency: CurrencyChoice

    @Parameter(title: "小数位", default: 1, inclusiveRange: (0, 3))
    var decimals: Int
}

struct RateIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "汇率"
    static let description = IntentDescription("任选两种货币的汇率")

    @Parameter(title: "从", default: .auto)
    var from: CurrencyChoice

    @Parameter(title: "到", default: .auto)
    var to: CurrencyChoice
}

// MARK: - Timeline

/// One minute of widget state, computed from the same config and caches the app uses.
struct PayEntry: TimelineEntry {
    var date: Date
    var config: Config?
    var snapshot: Snapshot?
    var rates: RateTable?
    /// Clock-out time while the workday is still running, for the live countdown.
    var offWork: Date?
    /// Resolved from the widget's settings: main / secondary currency (earnings) or from / to (rate).
    var currency = ""
    var altCurrency = ""
    var decimals = 1

    /// Converts an amount in the salary currency for display.
    func money(_ amount: Double, in code: String, _ digits: Int) -> String {
        guard let cfg = config else { return "--" }
        return formatMoney(convert(amount, from: cfg.currency, to: code, rates), code, digits)
    }
}

/// Entries a minute apart for the next hour; amounts refresh per entry, the countdown ticks on its own.
func timelineEntries(from start: Date, count: Int) -> [PayEntry] {
    let rates = readRateTable()
    let dates = (0..<count).map { start.addingTimeInterval(Double($0) * 60) }
    guard let cfg = try? loadConfig(), let salary = try? Salary(cfg) else {
        return dates.map { PayEntry(date: $0, rates: rates) }
    }
    let holidays = readHolidayCache(cfg.holidayRegion)
    return dates.map { date in
        let s = salary.snapshot(at: date, holidays: holidays, overtimeEnd: nil)
        let running = s.phase == .beforeWork || s.phase == .working || s.phase == .lunch
        let off = Calendar.current.startOfDay(for: date).addingTimeInterval(salary.end)
        return PayEntry(date: date, config: cfg, snapshot: s, rates: rates, offWork: running ? off : nil)
    }
}

private func minuteStart() -> Date {
    Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
}

struct EarningsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PayEntry { PayEntry(date: Date()) }

    func snapshot(for intent: EarningsIntent, in context: Context) async -> PayEntry {
        apply(intent, timelineEntries(from: Date(), count: 1))[0]
    }

    func timeline(for intent: EarningsIntent, in context: Context) async -> Timeline<PayEntry> {
        Timeline(entries: apply(intent, timelineEntries(from: minuteStart(), count: 60)), policy: .atEnd)
    }

    private func apply(_ intent: EarningsIntent, _ entries: [PayEntry]) -> [PayEntry] {
        entries.map { e in
            var e = e
            guard let cfg = e.config else { return e }
            e.currency = intent.currency.resolve(cfg.currency)
            let alt = intent.altCurrency.resolve(cfg.altCurrency)
            e.altCurrency = intent.showAlt && alt != e.currency ? alt : ""
            e.decimals = intent.decimals
            return e
        }
    }
}

struct RateProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PayEntry { PayEntry(date: Date()) }

    func snapshot(for intent: RateIntent, in context: Context) async -> PayEntry {
        apply(intent, timelineEntries(from: Date(), count: 1)[0])
    }

    func timeline(for intent: RateIntent, in context: Context) async -> Timeline<PayEntry> {
        // Rates change at most a few times a day; the app reloads widgets after each fetch.
        Timeline(entries: [apply(intent, timelineEntries(from: Date(), count: 1)[0])], policy: .after(Date() + 3600))
    }

    private func apply(_ intent: RateIntent, _ entry: PayEntry) -> PayEntry {
        var e = entry
        let base = e.config?.currency ?? "USD"
        e.currency = intent.from.resolve(base)
        let fallback = e.config.map { $0.altCurrency.isEmpty ? "" : $0.altCurrency } ?? ""
        e.altCurrency = intent.to.resolve(fallback.isEmpty ? (e.currency == "USD" ? "CNY" : "USD") : fallback)
        return e
    }
}

// MARK: - Views

private func dotColor(_ phase: Phase, _ accent: Color) -> Color {
    switch phase {
    case .working: accent
    case .lunch: .orange
    case .overtime: .red
    case .holiday: .pink
    default: .gray
    }
}

private struct SetupHint: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
}

struct EarningsView: View {
    let entry: PayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let cfg = entry.config, let s = entry.snapshot {
                if family == .systemMedium {
                    HStack(spacing: 16) {
                        main(cfg, s)
                        Divider()
                        details(cfg, s)
                    }
                } else {
                    main(cfg, s)
                }
            } else {
                SetupHint(text: L("打开薪跳完成设置"))
            }
        }
        .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
    }

    func main(_ cfg: Config, _ s: Snapshot) -> some View {
        let accent = Color(hex: cfg.accent)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(dotColor(s.phase, accent)).frame(width: 7, height: 7)
                Text(s.holidayName ?? s.phase.label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(verbatim: "\(Int(min(1, s.progress) * 100))%")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text(L("今日已赚")).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(entry.money(s.today, in: entry.currency, entry.decimals))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !entry.altCurrency.isEmpty {
                Text(verbatim: "≈ " + entry.money(s.today, in: entry.altCurrency, 0))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.15))
                    Capsule().fill(accent).frame(width: g.size.width * min(1, s.progress))
                }
            }
            .frame(height: 4)
            HStack {
                Text(L("距下班"))
                Spacer()
                if let off = entry.offWork {
                    Text(timerInterval: entry.date...off, countsDown: true).monospacedDigit()
                } else {
                    Text(s.phase.label)
                }
            }
            .font(.system(size: 11, weight: .medium))
            HStack {
                Text(L("距发薪"))
                Spacer()
                Text(s.daysToPay == 0 ? L("今天") : L("%d 天", s.daysToPay))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    func details(_ cfg: Config, _ s: Snapshot) -> some View {
        let digits = cfg.wholeRates ? 0 : 2
        let code = entry.currency
        return VStack(alignment: .leading, spacing: 6) {
            row(L("每秒进账"), entry.money(s.perSecond, in: code, 4))
            row(L("时薪"), entry.money(s.hourly, in: code, digits))
            row(L("日薪"), entry.money(s.daily, in: code, digits))
            row(L("本期已赚"), entry.money(s.cycle, in: code, 0))
            Spacer(minLength: 0)
            Text(cfg.messages[s.messageSlot.rawValue] ?? s.messageSlot.defaultText(at: entry.date))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

struct RateView: View {
    let entry: PayEntry

    var body: some View {
        Group {
            if let table = entry.rates, let r = convert(1, from: entry.currency, to: entry.altCurrency, table) {
                content(table, r)
            } else {
                SetupHint(text: L("汇率未获取"))
            }
        }
        .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
    }

    func content(_ table: RateTable, _ r: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L("汇率")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(verbatim: "\(entry.currency) → \(entry.altCurrency)")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Text(L("1 %@ =", currencyName(entry.currency))).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(formatMoney(r, entry.altCurrency, 4))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 2)
            HStack {
                Text(L("1 %@", currencyName(entry.altCurrency))).lineLimit(1)
                Spacer()
                Text(formatMoney(1 / r, entry.currency, 4)).monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            HStack {
                Text(L("更新"))
                Spacer()
                Text(table.updated.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute()))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Widgets

struct EarningsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "earnings", intent: EarningsIntent.self, provider: EarningsProvider()) {
            EarningsView(entry: $0)
        }
        .configurationDisplayName(L("今日已赚"))
        .description(L("今天赚了多少、离下班还有多久"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RateWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "rate", intent: RateIntent.self, provider: RateProvider()) {
            RateView(entry: $0)
        }
        .configurationDisplayName(L("汇率"))
        .description(L("任选两种货币的汇率"))
        .supportedFamilies([.systemSmall])
    }
}

@main
struct PayBeatWidgets: WidgetBundle {
    var body: some Widget {
        EarningsWidget()
        RateWidget()
    }
}
