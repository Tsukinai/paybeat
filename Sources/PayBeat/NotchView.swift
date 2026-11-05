import SwiftUI

@MainActor
final class NotchState: ObservableObject {
    @Published var expanded = false
    /// The hardware notch, or a stand-in on screens without one.
    @Published var notchSize = CGSize(width: 185, height: 32)
    /// Current size of the black shape, for hover hit-testing.
    var shapeSize = CGSize.zero
}

/// Black island hanging from the top edge: flared top corners blend into the screen edge like the notch.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { (top, bottom) = (newValue.first, newValue.second) }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var rates: RateStore
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var state: NotchState
    let onSettings: () -> Void
    @AppStorage("showAlt") private var showAlt = false

    private let ear: CGFloat = 6
    private let wing: CGFloat = 66
    private var look: Config { model.preview ?? model.config }
    private var accent: Color { Color(hex: look.accent) }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if state.expanded {
                    VStack(spacing: 0) {
                        Color.clear.frame(width: 0, height: state.notchSize.height)
                        CardView(
                            model: model, rates: rates, updates: updates,
                            onMinimize: {}, onSettings: onSettings, inNotch: true)
                    }
                } else {
                    TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
                        collapsed(model.snapshot(at: ctx.date))
                    }
                }
            }
            .transition(.opacity)
            .padding(.horizontal, ear)
            .background(NotchShape(top: ear, bottom: state.expanded ? 22 : 12).fill(Color.black))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { state.shapeSize = $0 }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: state.expanded)
    }

    func collapsed(_ s: Snapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Circle().fill(s.phase.color(accent)).frame(width: 7, height: 7)
                    Text(verbatim: "\(Int(min(1, s.progress) * 100))%")
                }
                .frame(width: wing)
                Color.clear.frame(width: state.notchSize.width)
                Text(rightWing(s)).lineLimit(1).minimumScaleFactor(0.7).frame(width: wing)
            }
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .frame(height: state.notchSize.height)
            Text(money(s.today, look.todayDecimals))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent)
                .padding(.bottom, 7)
        }
        .foregroundStyle(.white)
    }

    func rightWing(_ s: Snapshot) -> String {
        switch s.phase {
        case .working, .lunch, .beforeWork: hms(s.toOff)
        case .overtime: "+" + hms(s.overtime)
        default: s.holidayName ?? s.phase.label
        }
    }

    func money(_ amount: Double, _ digits: Int) -> String {
        let shown = model.display(amount, showAlt: showAlt)
        return formatMoney(shown.value, shown.code, digits)
    }
}
