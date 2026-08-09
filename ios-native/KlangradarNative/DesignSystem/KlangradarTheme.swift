import SwiftUI

enum KlangradarTheme {
    static let accent = Color(red: 0.08, green: 0.38, blue: 0.58)
    static let deepInk = Color(red: 0.025, green: 0.075, blue: 0.12)
    static let ice = Color(red: 0.94, green: 0.97, blue: 0.99)
    static let contentMaxWidth: CGFloat = 1_100
    static let pagePadding: CGFloat = 20

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
