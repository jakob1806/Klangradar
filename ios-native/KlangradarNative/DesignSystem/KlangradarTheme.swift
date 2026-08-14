import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum KlangradarTheme {
    static let defaultAccentHex = "#146194"
    static let accentStorageKey = "accentColorHex"
    static var accent: Color {
        color(hex: UserDefaults.standard.string(forKey: accentStorageKey) ?? defaultAccentHex)
            ?? color(hex: defaultAccentHex)!
    }
    static let deepInk = Color(red: 0.025, green: 0.075, blue: 0.12)
    static let ice = Color(red: 0.94, green: 0.97, blue: 0.99)
    static let contentMaxWidth: CGFloat = 1_100
    static let pagePadding: CGFloat = 20

    static func normalizedHex(_ input: String) -> String? {
        let value = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard value.count == 6, value.allSatisfy(\.isHexDigit) else { return nil }
        return "#\(value)"
    }

    static func color(hex input: String) -> Color? {
        guard let normalized = normalizedHex(input),
              let value = UInt64(normalized.dropFirst(), radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func hex(color: Color) -> String? {
#if canImport(UIKit)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
#else
        return nil
#endif
    }
}

struct KlangradarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.025, green: 0.05, blue: 0.075), Color(red: 0.055, green: 0.065, blue: 0.085)]
                : [Color(red: 0.93, green: 0.97, blue: 1.0), Color(red: 0.985, green: 0.985, blue: 0.995)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
