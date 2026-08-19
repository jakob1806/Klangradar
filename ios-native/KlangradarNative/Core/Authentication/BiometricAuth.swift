import Foundation
import LocalAuthentication

/// Dünner Wrapper um Face ID/Touch ID. Schützt NICHT den Netzwerk-Login
/// selbst (die Session liegt bereits in der Keychain, siehe
/// `AuthService.restoreOrCreateSession`), sondern gate't optional deren
/// Verwendung beim App-Start bzw. beim Öffnen sensibler Profil-Bereiche —
/// Nutzer-Wunsch "Face ID optional zum Schutz des Accounts".
enum BiometricAuth {
    /// UserDefaults-Key für den Nutzer-Toggle "Face ID zum Schutz nutzen"
    /// (Profil-Einstellungen), analog zu `KlangradarTheme.accentStorageKey`.
    static let enabledStorageKey = "faceIDProtectionEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledStorageKey)
    }

    enum BiometryKind {
        case none, touchID, faceID
    }

    /// Ob das Gerät überhaupt Face ID/Touch ID hat und es aktuell nutzbar
    /// ist (z. B. nicht durch zu viele Fehlversuche gesperrt) — bestimmt,
    /// ob der Einstellungen-Toggle überhaupt angeboten wird.
    static var availableBiometryKind: BiometryKind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    /// Fragt Face ID/Touch ID ab. Wirft bei Abbruch/Fehlschlag/fehlender
    /// Hardware — der Aufrufer entscheidet, ob er dann z. B. auf die
    /// Geräte-Passcode-Eingabe zurückfällt oder den Zugriff verweigert.
    /// `LAContext.evaluatePolicy` hat keine native async-Variante, daher
    /// die Continuation-Brücke um die Completion-Handler-API.
    @discardableResult
    static func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
