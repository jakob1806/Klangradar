import Foundation
import GroupActivities

/// SharePlay (02.11.2026): „Konzert gemeinsam ansehen“. Im FaceTime-Anruf
/// öffnet sich bei allen Teilnehmenden dieselbe Konzertseite.
struct ConcertTogetherActivity: GroupActivity {
    let slug: String
    let title: String

    static let activityIdentifier = "de.klangradar.native.concert-together"

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .generic
        metadata.title = title
        metadata.subtitle = "Gemeinsam in Klangradar ansehen"
        metadata.fallbackURL = URL(string: "https://klangradar.com/e/\(slug)")
        return metadata
    }

    /// Im Anruf direkt starten; sonst bietet iOS selbst an, SharePlay zu
    /// beginnen oder normal zu teilen.
    func startOrShare() async {
        switch await prepareForActivation() {
        case .activationPreferred:
            _ = try? await activate()
        case .activationDisabled, .cancelled:
            break
        @unknown default:
            break
        }
    }
}

/// Nimmt eingehende SharePlay-Sitzungen an und öffnet das Konzert.
@MainActor
enum ConcertTogetherCoordinator {
    private static var listening = false

    static func listen() async {
        guard !listening else { return }
        listening = true
        for await session in ConcertTogetherActivity.sessions() {
            session.join()
            DeepLinkRouter.shared.pendingEventSlug = session.activity.slug
        }
    }
}
