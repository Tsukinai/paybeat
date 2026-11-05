import Foundation

enum SalaryType: String, Codable, CaseIterable, Identifiable {
    case monthly, annual, hourly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .monthly: L("月薪")
        case .annual: L("年薪")
        case .hourly: L("时薪")
        }
    }
}

enum StatusBarMode: String, Codable, CaseIterable, Identifiable {
    case today, countdown, icon
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: L("今日已赚")
        case .countdown: L("距下班倒计时")
        case .icon: L("只显示图标")
        }
    }
}

enum MessageSlot: String, CaseIterable, Identifiable {
    case beforeWork, work0, work25, work50, work75, lunch, offWork, overtime, restDay, holiday
    var id: String { rawValue }
    var label: String {
        switch self {
        case .beforeWork: L("上班前")
        case .work0: L("进度 0–25%")
        case .work25: L("进度 25–50%")
        case .work50: L("进度 50–75%")
        case .work75: L("进度 75–100%")
        case .lunch: L("午休")
        case .offWork: L("下班后")
        case .overtime: L("加班中")
        case .restDay: L("休息日")
        case .holiday: L("节假日")
        }
    }
    var defaultText: String {
        switch self {
        case .beforeWork: L("还没开工，先吃早饭")
        case .work0: L("刚开工，慢慢进入状态")
        case .work25: L("稳住，钱在一秒一秒进账")
        case .work50: L("过半了，喝口水")
        case .work75: L("收尾阶段，别硬熬")
        case .lunch: L("午休中，好好吃饭")
        case .offWork: L("下班了，今天的钱已到手")
        case .overtime: L("加班中，记得早点回家")
        case .restDay: L("今天休息，别想工作")
        case .holiday: L("节日快乐，好好休息")
        }
    }
}

enum CardTheme: String, Codable, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dark: L("深色")
        case .light: L("浅色")
        case .system: L("跟随系统")
        }
    }
}

/// Accent colors offered in settings, as hex RGB.
let accentColors: [(name: String, hex: String)] = [
    ("green", "3DDC66"), ("teal", "2EC4B6"), ("blue", "4C8DFF"), ("purple", "A97BFF"),
    ("pink", "FF6FAE"), ("red", "FF5A5F"), ("orange", "FF9F43"), ("gold", "F2C94C"),
]

struct Config: Codable, Equatable {
    var salaryType = SalaryType.monthly
    var salary = 0.0
    /// Monthly salary only: months paid per year, e.g. 13 for a 13th-month bonus.
    var monthsPerYear = 12
    var currency = Config.localCurrency
    /// Currency to convert to when switching the display; empty means no conversion.
    var altCurrency = ""
    var workStart = "09:00"
    var workEnd = "18:00"
    var hasLunch = true
    var lunchStart = "12:00"
    var lunchEnd = "13:00"
    /// Calendar weekday numbers, 1 = Sunday.
    var workdays = [2, 3, 4, 5, 6]
    /// Holiday calendar region code; empty means weekdays only.
    var holidayRegion = Config.localRegion
    var payDay = 10
    var payEarlyOnHoliday = true
    /// Show hourly/daily rates on a fixed basis instead of the actual schedule.
    var customBasis = false
    var basisDays = 21.75
    var basisHours = 8.0
    var wholeRates = false
    var statusBar = StatusBarMode.today
    var overtime = false
    var overtimeRate = 1.0
    /// Custom messages keyed by MessageSlot raw value.
    var messages: [String: String] = [:]
    var checkUpdates = true
    var accent = "3DDC66"
    var theme = CardTheme.dark
    var opacity = 0.95
    var scale = 1.0
    var todayDecimals = 3
    var showRates = true
    var showProgress = true
    var showCycle = true
    var showMessage = true
    var showRateLine = true

    static var localCurrency: String {
        let code = Locale.current.currency?.identifier ?? "USD"
        return commonCurrencies.contains(code) ? code : "USD"
    }

    static var localRegion: String {
        let code = Locale.current.region?.identifier ?? ""
        return holidayRegions.contains(code) ? code : ""
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try c.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        salaryType = try value(.salaryType, d.salaryType)
        salary = try value(.salary, d.salary)
        monthsPerYear = try value(.monthsPerYear, d.monthsPerYear)
        currency = try value(.currency, d.currency)
        altCurrency = try value(.altCurrency, d.altCurrency)
        workStart = try value(.workStart, d.workStart)
        workEnd = try value(.workEnd, d.workEnd)
        hasLunch = try value(.hasLunch, d.hasLunch)
        lunchStart = try value(.lunchStart, d.lunchStart)
        lunchEnd = try value(.lunchEnd, d.lunchEnd)
        workdays = try value(.workdays, d.workdays)
        holidayRegion = try value(.holidayRegion, d.holidayRegion)
        payDay = try value(.payDay, d.payDay)
        payEarlyOnHoliday = try value(.payEarlyOnHoliday, d.payEarlyOnHoliday)
        customBasis = try value(.customBasis, d.customBasis)
        basisDays = try value(.basisDays, d.basisDays)
        basisHours = try value(.basisHours, d.basisHours)
        wholeRates = try value(.wholeRates, d.wholeRates)
        statusBar = try value(.statusBar, d.statusBar)
        overtime = try value(.overtime, d.overtime)
        overtimeRate = try value(.overtimeRate, d.overtimeRate)
        messages = try value(.messages, d.messages)
        checkUpdates = try value(.checkUpdates, d.checkUpdates)
        accent = try value(.accent, d.accent)
        theme = try value(.theme, d.theme)
        opacity = try value(.opacity, d.opacity)
        scale = try value(.scale, d.scale)
        todayDecimals = try value(.todayDecimals, d.todayDecimals)
        showRates = try value(.showRates, d.showRates)
        showProgress = try value(.showProgress, d.showProgress)
        showCycle = try value(.showCycle, d.showCycle)
        showMessage = try value(.showMessage, d.showMessage)
        showRateLine = try value(.showRateLine, d.showRateLine)

        // v1.0 stored a monthly salary in SGD and converted to CNY.
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        if !c.contains(.salary), let sgd = try legacy.decodeIfPresent(Double.self, forKey: .monthlySalarySGD) {
            salary = sgd
            currency = "SGD"
            altCurrency = "CNY"
        }
    }

    private enum LegacyKeys: String, CodingKey {
        case monthlySalarySGD
    }
}

struct ConfigError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// The real home directory; inside the widget's sandbox `homeDirectoryForCurrentUser` is the container.
let realHome: URL = {
    if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
        return URL(fileURLWithPath: String(cString: dir))
    }
    return FileManager.default.homeDirectoryForCurrentUser
}()
let configDir = realHome.appendingPathComponent(".config/work-ticker")
let configURL = configDir.appendingPathComponent("config.json")

func saveConfig(_ cfg: Config) throws {
    try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(cfg).write(to: configURL)
}

/// Returns nil on first run, when no config file exists yet.
func loadConfig() throws -> Config? {
    guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
    return try JSONDecoder().decode(Config.self, from: Data(contentsOf: configURL))
}

func secondsOfDay(_ s: String) throws -> Double {
    let p = s.split(separator: ":").compactMap { Int($0) }
    guard p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) else {
        throw ConfigError(L("时间格式应为 HH:mm，收到 \"%@\"", s))
    }
    return Double(p[0] * 3600 + p[1] * 60)
}
