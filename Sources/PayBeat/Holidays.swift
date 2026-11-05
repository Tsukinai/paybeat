import Foundation
import WidgetKit

/// One dated entry: a day off, or (China) a weekend that is a make-up workday.
struct HolidayDay: Codable {
    let date: String
    let off: Bool
    let name: String
}

struct HolidayCalendar {
    private var days: [Int: HolidayDay] = [:]

    static func key(_ date: Date, _ cal: Calendar) -> Int {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return c.year! * 10000 + c.month! * 100 + c.day!
    }

    func entry(_ date: Date, _ cal: Calendar) -> HolidayDay? {
        days[Self.key(date, cal)]
    }

    mutating func add(_ list: [HolidayDay]) {
        for day in list {
            let p = day.date.split(separator: "-").compactMap { Int($0) }
            if p.count == 3 { days[p[0] * 10000 + p[1] * 100 + p[2]] = day }
        }
    }
}

/// Countries covered by date.nager.at; China uses holiday-cn instead, which includes make-up workdays.
private let nagerCountries = """
    AD AG AI AL AM AO AR AT AU AW AX BA BB BD BE BF BG BH BI BJ BL BM BO BQ BR BS BW BY BZ CA CC CD CF CG CH CI \
    CK CL CM CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG ER ES ET FI FK FM FO FR GA GB GD GE GF GG GH GI GL \
    GM GN GP GQ GR GT GW GY HK HN HR HT HU ID IE IM IQ IS IT JE JM JP KE KH KI KM KN KR KY KZ LC LI LR LS LT LU LV \
    LY MA MC MD ME MF MG MH MK ML MN MP MQ MR MS MT MW MX MZ NA NC NE NF NG NI NL NO NR NU NZ PA PE PF PG PH PL PM \
    PN PR PT PW PY RO RS RU RW SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TG TK TN TO TR TT \
    TV TZ UA UG US UY VA VC VE VG VI VN VU WF WS YE ZA ZM ZW
    """.split(separator: " ").map(String.init)

let holidayRegions = ["CN"] + nagerCountries

func regionName(_ code: String) -> String {
    if code.isEmpty { return L("不使用") }
    if code == "CN" { return L("中国大陆（含调休）") }
    return Locale.current.localizedString(forRegionCode: code) ?? code
}

private let holidaysDir = configDir.appendingPathComponent("holidays")

private var holidayYears: [Int] {
    let y = Calendar.current.component(.year, from: Date())
    return [y - 1, y, y + 1]
}

private func holidayCacheURL(_ region: String, _ year: Int) -> URL {
    holidaysDir.appendingPathComponent("\(region)-\(year).json")
}

/// Reads the cached holidays for last, this and next year; also used by the widget.
func readHolidayCache(_ region: String) -> HolidayCalendar {
    var cal = HolidayCalendar()
    guard !region.isEmpty else { return cal }
    for y in holidayYears {
        if let data = try? Data(contentsOf: holidayCacheURL(region, y)),
            let days = try? JSONDecoder().decode([HolidayDay].self, from: data)
        {
            cal.add(days)
        }
    }
    return cal
}

@MainActor
final class HolidayStore: ObservableObject {
    @Published private(set) var calendars: [String: HolidayCalendar] = [:]
    private var lastFetch: [String: Date] = [:]

    func calendar(for region: String) -> HolidayCalendar {
        calendars[region] ?? HolidayCalendar()
    }

    /// Loads the disk cache, then refreshes from the network at most every 12 hours.
    func load(_ region: String) {
        guard !region.isEmpty else { return }
        if calendars[region] == nil { calendars[region] = readHolidayCache(region) }
        if let last = lastFetch[region], Date().timeIntervalSince(last) < 12 * 3600 { return }
        lastFetch[region] = Date()
        Task { await fetch(region) }
    }

    private func fetch(_ region: String) async {
        var changed = false
        for y in holidayYears {
            do {
                guard let days = try await download(region, y) else { continue }
                try FileManager.default.createDirectory(at: holidaysDir, withIntermediateDirectories: true)
                try JSONEncoder().encode(days).write(to: holidayCacheURL(region, y))
                changed = true
            } catch {
                log("节假日数据 \(region) \(y) 获取失败: \(error)")
            }
        }
        if changed {
            calendars[region] = readHolidayCache(region)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Returns nil when that year has not been published.
    private func download(_ region: String, _ year: Int) async throws -> [HolidayDay]? {
        if region == "CN" {
            struct Resp: Decodable {
                struct Day: Decodable {
                    let name: String
                    let date: String
                    let isOffDay: Bool
                }
                let days: [Day]
            }
            var lastError: Error = URLError(.badServerResponse)
            for base in [
                "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master",
                "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master",
            ] {
                do {
                    let (data, resp) = try await URLSession.shared.data(from: URL(string: "\(base)/\(year).json")!)
                    if (resp as? HTTPURLResponse)?.statusCode == 404 { return nil }
                    return try JSONDecoder().decode(Resp.self, from: data).days.map {
                        HolidayDay(date: $0.date, off: $0.isOffDay, name: $0.name)
                    }
                } catch {
                    lastError = error
                }
            }
            throw lastError
        }

        struct Day: Decodable {
            let date: String
            let localName: String
            let global: Bool
        }
        let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(region)")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 || status == 204 { return nil }
        return try JSONDecoder().decode([Day].self, from: data).filter(\.global).map {
            HolidayDay(date: $0.date, off: true, name: $0.localName)
        }
    }
}
