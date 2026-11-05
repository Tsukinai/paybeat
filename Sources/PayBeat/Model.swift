import AppKit
import WidgetKit

/// Every currency's rate against one base, as returned by open.er-api.com.
struct RateTable: Codable {
    var base: String
    var rates: [String: Double]
    var updated: Date
}

private let rateURL = configDir.appendingPathComponent("rate.json")

/// Last fetched rate table; also used by the widget.
func readRateTable() -> RateTable? {
    (try? Data(contentsOf: rateURL)).flatMap { try? JSONDecoder().decode(RateTable.self, from: $0) }
}

/// Converts between any two currencies in the table via its base.
func convert(_ amount: Double, from: String, to: String, _ table: RateTable?) -> Double? {
    if from == to { return amount }
    guard let table, let f = table.rates[from], let t = table.rates[to], f > 0 else { return nil }
    return amount / f * t
}

@MainActor
final class RateStore: ObservableObject {
    @Published private(set) var table: RateTable?
    private var timer: Timer?

    func rate(from base: String, to target: String) -> Double? {
        convert(1, from: base, to: target, table)
    }

    func configure(base: String) {
        timer?.invalidate()
        if table == nil { table = readRateTable() }
        refresh(base)
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(base) }
        }
    }

    private func refresh(_ base: String) {
        Task {
            struct Resp: Decodable {
                let result: String
                let time_last_update_unix: Double
                let rates: [String: Double]
            }
            do {
                let (data, _) = try await URLSession.shared.data(
                    from: URL(string: "https://open.er-api.com/v6/latest/\(base)")!)
                let r = try JSONDecoder().decode(Resp.self, from: data)
                guard r.result == "success" else { throw ConfigError("汇率接口返回 \(r.result)") }
                let t = RateTable(base: base, rates: r.rates, updated: Date(timeIntervalSince1970: r.time_last_update_unix))
                table = t
                try JSONEncoder().encode(t).write(to: rateURL)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                log("汇率更新失败: \(error)")
            }
        }
    }
}

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
let repoURL = URL(string: "https://github.com/Tsukinai/paybeat")!

func isNewer(_ tag: String, than current: String) -> Bool {
    func parts(_ s: String) -> [Int] {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "v")).split(separator: ".").map { Int($0) ?? 0 }
    }
    let a = parts(tag), b = parts(current)
    for i in 0..<max(a.count, b.count) {
        let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
        if x != y { return x > y }
    }
    return false
}

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var latestTag: String?
    @Published private(set) var latestURL: URL?
    private var timer: Timer?

    func start() {
        guard timer == nil, appVersion != nil else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        latestTag = nil
        latestURL = nil
    }

    private func check() {
        guard let appVersion else { return }
        Task {
            struct Release: Decodable {
                let tag_name: String
                let html_url: URL
            }
            do {
                let api = URL(string: "https://api.github.com/repos/Tsukinai/paybeat/releases/latest")!
                let (data, _) = try await URLSession.shared.data(from: api)
                let r = try JSONDecoder().decode(Release.self, from: data)
                if isNewer(r.tag_name, than: appVersion) {
                    latestTag = r.tag_name
                    latestURL = r.html_url
                }
            } catch {
                log("检查更新失败: \(error)")
            }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var config: Config
    @Published private(set) var salary: Salary
    @Published private(set) var overtimeEnd: Date?
    /// Unsaved settings draft, used only for how the card looks.
    @Published var preview: Config?
    let holidays: HolidayStore
    let rates: RateStore
    let updates: UpdateChecker
    private var timer: Timer?

    init(config: Config, holidays: HolidayStore, rates: RateStore, updates: UpdateChecker) throws {
        self.config = config
        salary = try Salary(config)
        overtimeEnd = UserDefaults.standard.object(forKey: "overtimeEnd") as? Date
        self.holidays = holidays
        self.rates = rates
        self.updates = updates
        startServices()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.holidays.load(self.config.holidayRegion)
            }
        }
    }

    func apply(_ new: Config) throws {
        let validated = try Salary(new)
        try saveConfig(new)
        config = new
        salary = validated
        startServices()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func startServices() {
        holidays.load(config.holidayRegion)
        rates.configure(base: config.currency)
        if config.checkUpdates { updates.start() } else { updates.stop() }
    }

    func snapshot(at now: Date = Date()) -> Snapshot {
        salary.snapshot(at: now, holidays: holidays.calendar(for: config.holidayRegion), overtimeEnd: overtimeEnd)
    }

    func stopOvertime() {
        overtimeEnd = Date()
        UserDefaults.standard.set(overtimeEnd, forKey: "overtimeEnd")
    }

    /// Converts an amount in the salary currency to whichever currency is being shown.
    func display(_ amount: Double, showAlt: Bool) -> (value: Double?, code: String) {
        guard showAlt, !config.altCurrency.isEmpty else { return (amount, config.currency) }
        return (rates.rate(from: config.currency, to: config.altCurrency).map { amount * $0 }, config.altCurrency)
    }
}
