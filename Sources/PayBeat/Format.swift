import SwiftUI

extension Color {
    init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0x3DDC66
        self.init(
            red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Localized string; keys are the Chinese source text, English lives in Localization/en.lproj.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}

func log(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let commonCurrencies = [
    "CNY", "USD", "SGD", "HKD", "TWD", "MOP", "JPY", "KRW", "EUR", "GBP", "AUD", "CAD",
    "NZD", "CHF", "MYR", "THB", "PHP", "IDR", "VND", "INR", "AED",
]

private let currencySymbols = [
    "CNY": "¥", "USD": "$", "SGD": "S$", "HKD": "HK$", "TWD": "NT$", "MOP": "MOP$", "JPY": "JP¥",
    "KRW": "₩", "EUR": "€", "GBP": "£", "AUD": "A$", "CAD": "C$", "NZD": "NZ$", "CHF": "CHF ",
    "MYR": "RM", "THB": "฿", "PHP": "₱", "IDR": "Rp", "VND": "₫", "INR": "₹", "AED": "AED ",
]

func currencySymbol(_ code: String) -> String {
    currencySymbols[code] ?? code + " "
}

func currencyName(_ code: String) -> String {
    Locale.current.localizedString(forCurrencyCode: code) ?? code
}

func formatMoney(_ value: Double?, _ code: String, _ digits: Int) -> String {
    guard let value else { return currencySymbol(code) + "--" }
    return currencySymbol(code)
        + value.formatted(.number.precision(.fractionLength(digits)).rounded(rule: .toNearestOrAwayFromZero))
}

func hms(_ t: Double) -> String {
    let s = Int(t)
    return String(format: "%02d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
}

func timeOfDay(_ s: String) -> Date {
    Calendar.current.startOfDay(for: Date()).addingTimeInterval((try? secondsOfDay(s)) ?? 0)
}

func hhmm(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
    return String(format: "%02d:%02d", c.hour!, c.minute!)
}

extension Phase {
    /// Status dot color.
    func color(_ accent: Color) -> Color {
        switch self {
        case .working: accent
        case .lunch: .orange
        case .overtime: .red
        case .holiday: .pink
        default: .gray
        }
    }
}
