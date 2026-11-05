// Renders the 1024px app icon. Usage: swift Icon/make_icon.swift <out.png>
// Then build the .icns with Icon/build.sh.
import AppKit
import SwiftUI

let green = Color(red: 0.24, green: 0.86, blue: 0.40)
let teal = Color(red: 0.18, green: 0.77, blue: 0.71)

/// Heartbeat trace across the icon body, in 1024px canvas coordinates.
struct Pulse: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (190, 560), (370, 560), (410, 515), (450, 560), (480, 610), (540, 290),
            (605, 720), (645, 560), (720, 560), (770, 505), (820, 560), (834, 560),
        ]
        var p = Path()
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for (x, y) in pts.dropFirst() { p.addLine(to: CGPoint(x: x, y: y)) }
        return p
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.15, green: 0.17, blue: 0.20), Color(red: 0.05, green: 0.06, blue: 0.08)],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            // Faint ECG-paper grid.
            Path { p in
                for i in stride(from: 100.0, through: 924.0, by: 68.67) {
                    p.move(to: CGPoint(x: i, y: 100)); p.addLine(to: CGPoint(x: i, y: 924))
                    p.move(to: CGPoint(x: 100, y: i)); p.addLine(to: CGPoint(x: 924, y: i))
                }
            }
            .stroke(Color.white.opacity(0.05), lineWidth: 3)
            .mask(RoundedRectangle(cornerRadius: 185, style: .continuous).frame(width: 824, height: 824))
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 4)
                .frame(width: 820, height: 820)
            Pulse()
                .stroke(green.opacity(0.55), style: StrokeStyle(lineWidth: 46, lineCap: .round, lineJoin: .round))
                .blur(radius: 28)
            Pulse()
                .stroke(
                    LinearGradient(colors: [green, teal], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 44, lineCap: .round, lineJoin: .round))
            Circle()
                .fill(Color.white)
                .frame(width: 34, height: 34)
                .shadow(color: green, radius: 16)
                .position(x: 834, y: 560)
        }
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
