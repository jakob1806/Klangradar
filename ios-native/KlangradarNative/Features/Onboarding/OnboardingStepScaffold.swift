import SwiftUI

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
                    .buttonStyle(.borderedProminent)
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
