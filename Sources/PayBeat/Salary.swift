import Foundation

enum Phase {
    case restDay, holiday, beforeWork, working, lunch, offWork, overtime

    var label: String {
        switch self {
        case .restDay: L("休息日")
        case .holiday: L("节假日")
        case .beforeWork: L("未上班")
        case .working: L("在岗")
        case .lunch: L("午休")
        case .offWork: L("已下班")
        case .overtime: L("加班中")
        }
    }
}

struct Snapshot {
    let phase: Phase
    let holidayName: String?
    let worked: Double
    let toOff: Double
    let progress: Double
    let overtime: Double
    let perSecond: Double
    let today: Double
    let cycle: Double
    let cycleWorkdays: Int
    let daysToPay: Int
    /// Rates as shown on the card (actual or custom basis).
    let daily: Double
    let hourly: Double

    var messageSlot: MessageSlot {
        switch phase {
        case .restDay: .restDay
        case .holiday: .holiday
        case .beforeWork: .beforeWork
        case .lunch: .lunch
        case .offWork: .offWork
        case .overtime: .overtime
        case .working:
            progress < 0.25 ? .work0 : progress < 0.5 ? .work25 : progress < 0.75 ? .work50 : .work75
        }
    }
}

struct Salary {
    let config: Config
    let start, end, lunchStart, lunchEnd: Double
    let workSeconds: Double

    init(_ cfg: Config) throws {
        guard cfg.salary > 0 else { throw ConfigError(L("请填写工资")) }
        start = try secondsOfDay(cfg.workStart)
        end = try secondsOfDay(cfg.workEnd)
        guard start < end else { throw ConfigError(L("下班时间要晚于上班时间")) }
        if cfg.hasLunch {
            lunchStart = try secondsOfDay(cfg.lunchStart)
            lunchEnd = try secondsOfDay(cfg.lunchEnd)
            guard start < lunchStart, lunchStart <= lunchEnd, lunchEnd < end else {
                throw ConfigError(L("午休要在上下班时间之间，且开始不晚于结束"))
            }
        } else {
            lunchStart = end
            lunchEnd = end
        }
        guard !cfg.workdays.isEmpty else { throw ConfigError(L("至少选一个工作日")) }
        guard (1...31).contains(cfg.payDay) else { throw ConfigError(L("发薪日需在 1 到 31 之间")) }
        guard (1...24).contains(cfg.monthsPerYear) else { throw ConfigError(L("每年发薪月数需在 1 到 24 之间")) }
        if cfg.customBasis {
            guard cfg.basisDays > 0, cfg.basisHours > 0 else {
                throw ConfigError(L("时薪/日薪的天数和小时数需大于 0"))
            }
        }
        guard cfg.overtimeRate >= 0 else { throw ConfigError(L("加班倍率不能小于 0")) }
        guard cfg.altCurrency != cfg.currency else { throw ConfigError(L("换算币种不能和工资币种相同")) }
        workSeconds = (end - start) - (lunchEnd - lunchStart)
        config = cfg
    }

    /// Income per pay cycle for monthly and annual salaries.
    var monthlyIncome: Double {
        switch config.salaryType {
        case .monthly: config.salary * Double(config.monthsPerYear) / 12
        case .annual: config.salary / 12
        case .hourly: 0
        }
    }

    func isWorkday(_ day: Date, _ holidays: HolidayCalendar, _ cal: Calendar) -> Bool {
        if let entry = holidays.entry(day, cal) { return !entry.off }
        return config.workdays.contains(cal.component(.weekday, from: day))
    }

    /// Pay date for the month starting at `monthStart`; short months pay on their last day.
    func payDate(_ monthStart: Date, _ holidays: HolidayCalendar, _ cal: Calendar) -> Date {
        let length = cal.range(of: .day, in: .month, for: monthStart)!.count
        var day = cal.date(byAdding: .day, value: min(config.payDay, length) - 1, to: monthStart)!
        var steps = 0
        while config.payEarlyOnHoliday, !isWorkday(day, holidays, cal), steps < 31 {
            day = cal.date(byAdding: .day, value: -1, to: day)!
            steps += 1
        }
        return day
    }

    func snapshot(at now: Date, holidays: HolidayCalendar, overtimeEnd: Date?, cal: Calendar = .current) -> Snapshot {
        let todayStart = cal.startOfDay(for: now)
        let t = now.timeIntervalSince(todayStart)
        let holiday = holidays.entry(now, cal)
        let workday = isWorkday(now, holidays, cal)
        let worked = workday ? max(0, min(t, lunchStart) - start) + max(0, min(t, end) - lunchEnd) : 0

        var overtime = 0.0
        var overtimeRunning = false
        if workday, config.overtime, t >= end {
            let endDate = todayStart.addingTimeInterval(end)
            if let stop = overtimeEnd, stop >= endDate, cal.isDate(stop, inSameDayAs: now) {
                overtime = min(now, stop).timeIntervalSince(endDate)
            } else {
                overtime = now.timeIntervalSince(endDate)
                overtimeRunning = true
            }
        }

        let phase: Phase
        if !workday { phase = holiday?.off == true ? .holiday : .restDay }
        else if t < start { phase = .beforeWork }
        else if t < lunchStart { phase = .working }
        else if t < lunchEnd { phase = .lunch }
        else if t < end { phase = .working }
        else if overtimeRunning { phase = .overtime }
        else { phase = .offWork }

        // Pay cycle: the day after the previous pay date through the next pay date.
        var month = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        var cycleEnd = payDate(month, holidays, cal)
        while todayStart > cycleEnd {
            month = cal.date(byAdding: .month, value: 1, to: month)!
            cycleEnd = payDate(month, holidays, cal)
        }
        let previousPay = payDate(cal.date(byAdding: .month, value: -1, to: month)!, holidays, cal)
        var total = 0, before = 0
        var day = cal.date(byAdding: .day, value: 1, to: previousPay)!
        while day <= cycleEnd {
            if isWorkday(day, holidays, cal) {
                total += 1
                if day < todayStart { before += 1 }
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }

        let daily: Double, perSecond: Double
        if config.salaryType == .hourly {
            perSecond = config.salary / 3600
            daily = perSecond * workSeconds
        } else {
            daily = total > 0 ? monthlyIncome / Double(total) : 0
            perSecond = daily / workSeconds
        }
        let today = perSecond * (worked + overtime * config.overtimeRate)

        let shownDaily: Double, shownHourly: Double
        if config.salaryType == .hourly {
            shownDaily = daily
            shownHourly = config.salary
        } else if config.customBasis {
            shownDaily = monthlyIncome / config.basisDays
            shownHourly = shownDaily / config.basisHours
        } else {
            shownDaily = daily
            shownHourly = daily / (workSeconds / 3600)
        }

        return Snapshot(
            phase: phase,
            holidayName: holiday?.off == true ? holiday?.name : nil,
            worked: worked,
            toOff: workday ? max(0, end - t) : 0,
            progress: worked / workSeconds,
            overtime: overtime,
            perSecond: perSecond,
            today: today,
            cycle: Double(before) * daily + today,
            cycleWorkdays: total,
            daysToPay: cal.dateComponents([.day], from: todayStart, to: cycleEnd).day!,
            daily: shownDaily,
            hourly: shownHourly)
    }
}
