import SwiftUI
import UIKit

struct KlangradarAppIcon: View {
    var size: CGFloat = 76

    private var image: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let name = files.last
        else { return UIImage(named: "AppIcon") }
        return UIImage(named: name)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image("AppIcon").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 7)
        .accessibilityHidden(true)
    }
}

struct OnboardingProgressHeader: View {
    let current: Int
    let total: Int

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Schritt \(current) von \(total)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ProgressView(value: Double(current), total: Double(total))
                .tint(KlangradarTheme.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.clear)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    @ViewBuilder
    func authPrimaryButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func authSecondaryButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func authBottomActionLayout() -> some View {
        if #available(iOS 26.0, *) {
            self.padding(.horizontal, 20).padding(.vertical, 10)
        } else {
            self.padding().background(.bar)
        }
    }
}

/// Gemeinsames Gerüst für kompakte Onboarding-Schritte (Titel + Inhalt +
/// primärer "Weiter"-Button, optional ein sekundärer Text-Button zum
/// Überspringen). Schritte mit einer eingebetteten Liste/Form (Interessen,
/// Benachrichtigungen) nutzen stattdessen ihr eigenes Layout, siehe
/// InterestsStepView/NotificationsStepView.
struct OnboardingStepScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content
    let primaryTitle: String
    var isPrimaryEnabled: Bool = true
    let onPrimary: () -> Void
    var secondaryTitle: String? = nil
    var onSecondary: (() -> Void)? = nil
    var errorMessage: String? = nil
    var isWorking: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 8)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 52))
                    .foregroundStyle(KlangradarTheme.accent)
            }
            VStack(spacing: 8) {
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            content()

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button(primaryTitle) { onPrimary() }
                    .authPrimaryButtonStyle()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(!isPrimaryEnabled || isWorking)

                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle) { onSecondary() }
                        .font(.footnote)
                        .disabled(isWorking)
                }
            }
        }
        .padding(28)
        .overlay {
            if isWorking {
                ProgressView().controlSize(.large)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
