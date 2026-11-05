import AppKit

struct RateCache: Codable {
    var base: String
    var target: String
    var rate: Double
    var updated: Date
}

@MainActor
final class RateStore: ObservableObject {
    @Published private(set) var cache: RateCache?
    private var timer: Timer?
    private let url = configDir.appendingPathComponent("rate.json")

    func rate(from base: String, to target: String) -> Double? {
        guard let cache, cache.base == base, cache.target == target else { return nil }
        return cache.rate
    }

    func configure(base: String, target: String) {
        timer?.invalidate()
        timer = nil
        guard !target.isEmpty else { return }
        if rate(from: base, to: target) == nil {
            cache = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(RateCache.self, from: $0) }
        }
        refresh(base, target)
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(base, target) }
        }
    }

    private func refresh(_ base: String, _ target: String) {
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
                guard r.result == "success", let rate = r.rates[target] else {
                    throw ConfigError("汇率接口返回 \(r.result)，无 \(target)")
                }
                let c = RateCache(base: base, target: target, rate: rate,
                                  updated: Date(timeIntervalSince1970: r.time_last_update_unix))
                cache = c
                try JSONEncoder().encode(c).write(to: url)
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
    }

    private func startServices() {
        holidays.load(config.holidayRegion)
        rates.configure(base: config.currency, target: config.altCurrency)
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
