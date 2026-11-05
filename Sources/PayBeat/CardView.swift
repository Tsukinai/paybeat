import SwiftUI

struct CardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var rates: RateStore
    @ObservedObject var updates: UpdateChecker
    let onMinimize: () -> Void
    let onSettings: () -> Void
    @AppStorage("showAlt") private var showAlt = false
    @Environment(\.colorScheme) private var systemScheme

    /// Looks follow the settings draft while the settings window is open.
    private var look: Config { model.preview ?? model.config }
    private var accent: Color { Color(hex: look.accent) }
    private var scheme: ColorScheme {
        switch look.theme {
        case .dark: .dark
        case .light: .light
        case .system: systemScheme
        }
    }

    private func f(_ size: CGFloat) -> CGFloat { size * look.scale }

    /// Drawn inside the notch panel: no own background, no dragging, no minimize button.
    var inNotch = false

    var body: some View {
        let card = TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            content(model.snapshot(at: ctx.date), at: ctx.date)
        }
        .padding(f(16))
        .frame(width: f(320))
        if inNotch {
            card.contextMenu { menuItems }
        } else {
            card
                .background(
                    RoundedRectangle(cornerRadius: f(14))
                        .fill(scheme == .dark ? Color(red: 0.11, green: 0.13, blue: 0.15) : Color(white: 0.97))
                        .opacity(look.opacity)
                )
                .overlay(RoundedRectangle(cornerRadius: f(14)).stroke(Color.primary.opacity(0.08)))
                .environment(\.colorScheme, scheme)
                .gesture(WindowDragGesture())
                .contextMenu { menuItems }
        }
    }

    @ViewBuilder var menuItems: some View {
        if !model.config.altCurrency.isEmpty {
            Button(L("显示%@", currencyName(showAlt ? model.config.currency : model.config.altCurrency))) {
                showAlt.toggle()
            }
        }
        Button(L("设置…"), action: onSettings)
        if let tag = updates.latestTag, let url = updates.latestURL {
            Button(L("下载新版本 %@", tag)) { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button(L("退出")) { NSApp.terminate(nil) }
    }

    func money(_ amount: Double, _ digits: Int) -> String {
        let shown = model.display(amount, showAlt: showAlt)
        return formatMoney(shown.value, shown.code, digits)
    }

    func content(_ s: Snapshot, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: f(10)) {
            HStack(spacing: f(6)) {
                Text(L("今日已赚")).font(.system(size: f(12))).foregroundStyle(.secondary)
                Spacer()
                if s.phase == .overtime {
                    Button(L("下班")) { model.stopOvertime() }.controlSize(.small)
                }
                badge(s)
                if !inNotch {
                    Button(action: onMinimize) {
                    Image(systemName: "minus")
                        .font(.system(size: f(10), weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: f(20), height: f(20))
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(money(s.today, look.todayDecimals))
                .font(.system(size: f(34), weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .contentShape(Rectangle())
                .onTapGesture { if !model.config.altCurrency.isEmpty { showAlt.toggle() } }
            if look.showRates {
                HStack(alignment: .top) {
                    stat(L("每秒进账"), money(s.perSecond, 4))
                    stat(L("时薪"), money(s.hourly, look.wholeRates ? 0 : 2))
                    stat(L("日薪"), money(s.daily, look.wholeRates ? 0 : 2))
                }
            }
            if look.showProgress {
                Divider()
                HStack {
                    Text(L("已工作 %@", hms(s.worked)))
                    Spacer()
                    Text(verbatim: "\(Int(min(1, s.progress) * 100))%")
                    Spacer()
                    if s.overtime > 0 {
                        Text(L("加班 %@", hms(s.overtime))).foregroundStyle(.orange)
                    } else {
                        Text(L("距下班 %@", hms(s.toOff))).foregroundStyle(accent)
                    }
                }
                .font(.system(size: f(12)))
                .monospacedDigit()
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [accent.opacity(0.6), accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * min(1, s.progress))
                    }
                }
                .frame(height: f(6))
            }
            if look.showCycle {
                HStack {
                    Text(L("本期已赚 %@", money(s.cycle, 2)))
                    Spacer()
                    Text(s.daysToPay == 0 ? L("今天发工资") : L("距发工资 %d 天", s.daysToPay))
                }
                .font(.system(size: f(12)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            if look.showMessage {
                Text(look.messages[s.messageSlot.rawValue] ?? s.messageSlot.defaultText(at: date))
                    .font(.system(size: f(13)))
                    .frame(maxWidth: .infinity)
            }
            if look.showRateLine, let line = rateLine {
                Text(line)
                    .font(.system(size: f(10)))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            if let tag = updates.latestTag, let url = updates.latestURL {
                Link(L("有新版本 %@", tag), destination: url)
                    .font(.system(size: f(10)))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    var rateLine: String? {
        let cfg = model.config
        guard !cfg.altCurrency.isEmpty else { return nil }
        guard let table = rates.table, let rate = rates.rate(from: cfg.currency, to: cfg.altCurrency) else {
            return L("汇率未获取")
        }
        return L(
            "1 %@ = %@ %@ · %@ 更新", cfg.currency, rate.formatted(.number.precision(.fractionLength(4))),
            cfg.altCurrency, table.updated.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
    }

    func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: f(2)) {
            Text(title).font(.system(size: f(11))).foregroundStyle(.secondary)
            Text(value).font(.system(size: f(14), weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func badge(_ s: Snapshot) -> some View {
        let color: Color =
            switch s.phase {
            case .working: accent
            case .lunch: .orange
            case .overtime: .red
            case .holiday: .pink
            default: .gray
            }
        return HStack(spacing: f(4)) {
            Circle().fill(color).frame(width: f(6), height: f(6))
            Text(s.holidayName ?? s.phase.label).font(.system(size: f(11), weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, f(8))
        .padding(.vertical, f(3))
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.18)))
    }
}
