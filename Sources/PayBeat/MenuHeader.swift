import SwiftUI

/// Summary shown at the top of the menu bar item's menu.
struct MenuHeader: View {
    @ObservedObject var model: AppModel
    @AppStorage("showAlt") private var showAlt = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            content(model.snapshot(at: ctx.date))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 280, alignment: .leading)
    }

    func money(_ amount: Double, _ digits: Int, alt: Bool) -> String {
        let shown = model.display(amount, showAlt: alt)
        return formatMoney(shown.value, shown.code, digits)
    }

    func content(_ s: Snapshot) -> some View {
        let accent = Color(hex: model.config.accent)
        let hasAlt = !model.config.altCurrency.isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("今日已赚")).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(s.phase.color(accent)).frame(width: 6, height: 6)
                Text(s.holidayName ?? s.phase.label)
            }
            .font(.system(size: 11, weight: .medium))
            Text(money(s.today, 2, alt: showAlt))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
            if hasAlt {
                Text(verbatim: "≈ " + money(s.today, 0, alt: !showAlt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule().fill(accent).frame(width: g.size.width * min(1, s.progress))
                    }
                }
                .frame(height: 5)
                Text(verbatim: "\(Int(min(1, s.progress) * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
            HStack {
                Text(L("已工作 %@", hms(s.worked)))
                Spacer()
                Text(s.overtime > 0 ? L("加班 %@", hms(s.overtime)) : L("距下班 %@", hms(s.toOff)))
            }
            .font(.system(size: 11))
            .monospacedDigit()
            HStack {
                Text(L("本期已赚 %@", money(s.cycle, 0, alt: showAlt)))
                Spacer()
                Text(s.daysToPay == 0 ? L("今天发工资") : L("距发工资 %d 天", s.daysToPay))
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}
