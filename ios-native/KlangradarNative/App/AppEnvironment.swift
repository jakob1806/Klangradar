import Foundation

struct AppEnvironment {
    let events: any EventRepository
    let content: any ContentRepository
    let restClient: SupabaseRESTClient?
    let auth: AuthStore
    let isUsingPreviewData: Bool

    @MainActor
    static func make(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) -> AppEnvironment {
        guard let configuration = APIConfiguration.load(
            processInfo: processInfo,
            bundle: bundle
        ) else {
            // Preview-Daten sind ausschließlich für Xcode-Previews und Tests
            // gedacht. Ein Geräte-Build wird zusätzlich im Deploy-Skript
            // blockiert, wenn Secrets.plist fehlt, damit niemals unbemerkt
            // eine scheinbar echte App ohne Supabase installiert wird.
            return AppEnvironment(
                events: PreviewEventRepository(),
                content: PreviewContentRepository(),
                restClient: nil,
                auth: AuthStore(service: nil),
                isUsingPreviewData: true
            )
        }

        let client = SupabaseRESTClient(configuration: configuration)
        return AppEnvironment(
            events: LiveEventRepository(client: client),
            content: LiveContentRepository(client: client),
            restClient: client,
            auth: AuthStore(service: AuthService(configuration: configuration)),
            isUsingPreviewData: false
        )
    }
}
