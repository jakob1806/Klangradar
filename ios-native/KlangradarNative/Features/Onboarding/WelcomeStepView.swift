import SwiftUI

/// Einstiegs-Schritt: Anmelden (bestehender Account) / Account erstellen /
/// ohne Account fortfahren (Gast, bleibt auf der anonymen Bootstrap-Session
/// aus main.dart-Äquivalent AppEnvironment).
///
/// Neugestaltung von Claude Code (Nutzerwunsch 27.10.2026): oben ein
/// langsam laufendes Mosaik echter Künstler:innen-Porträts aus Klangradar,
/// darunter Titel und ein kompakter Anmeldeblock (auf dem iPad zentriert
/// statt bildschirmbreit). Abgebrochene Apple-/Google-Anmeldungen zeigen
/// keinen (englischen) Fehler mehr.
struct WelcomeStepView: View {
    @ObservedObject var auth: AuthStore
    var client: SupabaseRESTClient? = nil
    let onCreateAccount: () -> Void
    let onLogIn: () -> Void
    let onContinueAsGuest: () -> Void
    let onAuthenticated: () -> Void

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var portraits: [URL] = []

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                PortraitMosaic(urls: portraits)
                    // iPad: deutlich höher, sonst bleibt unter dem Titel eine große Leere.
                    .frame(height: geo.size.width > 700 ? geo.size.height * 0.56 : min(geo.size.height * 0.42, 420))
                    // Oben weich ausblenden (Statusleiste lesbar), unten in den Hintergrund.
                    .mask(LinearGradient(stops: [.init(color: .black.opacity(0.15), location: 0), .init(color: .black, location: 0.18), .init(color: .black, location: 0.6), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                    .ignoresSafeArea(edges: .top)
                    .accessibilityHidden(true)

                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        KlangradarAppIcon(size: 64)
                        Text("Klassik live erleben")
                            .font(.system(.largeTitle, design: .serif).weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("Konzerte, Künstler:innen und Spielstätten deiner Stadt – entdecken, planen, erinnern.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    actions
                }
                .padding(.horizontal, 24)
                .padding(.top, -36)
                .padding(.bottom, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden()
        .onboardingChrome()
        .background { KlangradarBackground().ignoresSafeArea() }
        .overlay { if isWorking { ProgressView().controlSize(.large) } }
        .task { await loadPortraits() }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if auth.isAppleSignInAvailable {
                Button { Task { await oauth { try await auth.signInWithApple() } } } label: {
                    Label("Mit Apple fortfahren", systemImage: "apple.logo")
                        .font(.headline)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .background(Color.primary, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
            if auth.isGoogleSignInAvailable {
                Button { Task { await oauth { try await auth.signInWithGoogle() } } } label: {
                    GoogleSignInLabel()
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Color(uiColor: .systemBackground), in: .capsule)
                        .overlay(Capsule().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
            HStack(spacing: 12) {
                Button(action: onLogIn) {
                    Text("Anmelden").font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(KlangradarTheme.accent, in: .capsule)
                Button(action: onCreateAccount) {
                    Text("Konto erstellen").font(.headline).frame(maxWidth: .infinity).frame(height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(KlangradarTheme.accent)
                .background(KlangradarTheme.accent.opacity(0.12), in: .capsule)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button(action: onContinueAsGuest) {
                Text("Erst einmal umsehen – ohne Konto")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private func loadPortraits() async {
        guard portraits.isEmpty, let client else { return }
        let rows: [JSONObject] = (try? await client.rpc("onboarding_follow_suggestions", parameters: [
            "p_kind": .string("person"), "p_limit": .number(90)
        ])) ?? []
        let urls = rows.compactMap { $0.string("photo_url").flatMap(URL.init(string:)) }
        withAnimation(.easeIn(duration: 0.6)) { portraits = Array(urls.prefix(60)) }
    }

    private func oauth(_ action: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await action()
            onAuthenticated()
        } catch {
            guard !Self.isCancellation(error) else { return }
            errorMessage = "Anmeldung hat nicht geklappt. Bitte versuche es erneut."
        }
    }

    /// Abbruch durch den Nutzer: Apple (AuthorizationError 1001), Web-Login
    /// (ASWebAuthenticationSession 1), Google (GIDSignIn -5), Swift-Task.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case ("com.apple.AuthenticationServices.AuthorizationError", 1001),
             ("com.apple.AuthenticationServices.WebAuthenticationSession", 1),
             ("com.google.GIDSignIn", -5):
            return true
        default:
            return false
        }
    }
}

/// Drei Reihen runder Porträts, die gegeneinander langsam durchlaufen.
private struct PortraitMosaic: View {
    let urls: [URL]

    var body: some View {
        GeometryReader { geo in
            let rowHeight = (geo.size.height - 24) / 3
            TimelineView(.animation(minimumInterval: 1 / 30, paused: urls.isEmpty)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                VStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { row in
                        let items = rowItems(row)
                        let tile = rowHeight
                        let span = CGFloat(max(items.count, 1)) * (tile + 12)
                        let speed = [14.0, 10.0, 18.0][row]
                        let raw = CGFloat(t * speed).truncatingRemainder(dividingBy: max(span, 1))
                        let offset = row.isMultiple(of: 2) ? -raw : raw - span
                        HStack(spacing: 12) {
                            ForEach(Array((items + items + items).enumerated()), id: \.offset) { _, url in
                                CachedAsyncImage(url: url) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() }
                                    else { KlangradarTheme.accent.opacity(0.10) }
                                }
                                .frame(width: tile, height: tile)
                                .clipShape(.rect(cornerRadius: tile * 0.32, style: .continuous))
                            }
                        }
                        .offset(x: offset)
                        .frame(width: geo.size.width, alignment: .leading)
                    }
                }
                .clipped()
            }
            .overlay {
                if urls.isEmpty {
                    LinearGradient(colors: [KlangradarTheme.accent.opacity(0.25), .purple.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
    }

    private func rowItems(_ row: Int) -> [URL] {
        guard !urls.isEmpty else { return [] }
        return urls.enumerated().filter { $0.offset % 3 == row }.map(\.element)
    }
}
