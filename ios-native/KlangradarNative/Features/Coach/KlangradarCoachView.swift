// Aus ProfileView.swift ausgelagert (09.11.2026): Klangradar KI (Konzertführer).
import SwiftUI
import UIKit

struct KlangradarCoachView: View {
    @State private var showsPlusPaywall = false
    private enum Section: String, CaseIterable { case overview = "Heute", chat = "KI fragen" }
    // Nutzerfeedback: "Antworten sollen nicht reiner Text sein, sondern
    // kurzer Text plus kleine Konzert-Miniaturen zum Durchscrollen" -- jede
    // Assistenten-Nachricht trägt jetzt ihre eigenen Treffer (max. 4,
    // horizontal), statt einer einzigen globalen Liste unter dem ganzen
    // Verlauf.
    private struct ChatMessage: Identifiable {
        let id = UUID()
        let text: String
        let user: Bool
        var events: [CoachEvent] = []
        var eventsAreAlternatives = false
    }

    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    private let showsDismissButton: Bool
    private let presentsChatDirectly: Bool
    @EnvironmentObject private var favorites: FavoriteStore
    @EnvironmentObject private var cityStore: CityStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSection: Section
    @State private var dashboard: CoachDashboard?
    @State private var conversationID: UUID?
    @State private var messages: [ChatMessage] = [
        .init(text: "Frag mich nach deinem Geschmack, deinen Gewohnheiten oder einem konkreten Konzertabend. Ich nutze nur belegbare Klangradar-Daten und sage dir, wenn ich dich noch nicht gut genug kenne.", user: false)
    ]
    @State private var suggestedPrompts = ["Was passt dieses Wochenende zu mir?", "Erkläre mein Geschmacksprofil", "Plane einen Abend unter 50 €"]
    @State private var memoryProposal: JSONObject?
    @State private var goalProposal: JSONObject?
    @State private var draft = ""
    @State private var retryDraft: String?
    @State private var isLoading = false
    // Eigenes Flag fürs Senden: loadDashboard() setzte bisher dasselbe isLoading,
    // dadurch wurde jedes Senden (z. B. per Vorschlag) still verworfen und der
    // Pfeil zeigte schon das Stopp-Quadrat, solange das Dashboard lud.
    @State private var isSending = false
    // Nutzerfeedback: der Senden-Button soll sich während des Wartens auf
    // die Antwort in ein Stopp-Quadrat verwandeln (wie beim Senden einer
    // Anfrage an Claude) statt nur einen "denkt nach"-Text zu zeigen --
    // dieser Task-Handle macht den Abbruch tatsächlich wirksam, nicht nur
    // optisch.
    @State private var sendTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showsCheckin = false
    private let context: CoachContext

    init(
        auth: AuthStore,
        repository: UserRepository?,
        eventRepository: any EventRepository,
        contentRepository: any ContentRepository,
        startsInChat: Bool = false,
        showsDismissButton: Bool = false,
        context: CoachContext = .home
    ) {
        self.context = context
        _suggestedPrompts = State(initialValue: context.suggestedPrompts)
        self.auth = auth
        self.repository = repository
        self.eventRepository = eventRepository
        self.contentRepository = contentRepository
        self.showsDismissButton = showsDismissButton
        self.presentsChatDirectly = startsInChat
        // Nutzerwunsch 24.10.2026: nur noch die KI, kein "Heute"-Bereich.
        _selectedSection = State(initialValue: .chat)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch selectedSection {
            case .overview: overview
            case .chat: chat
            }
        }
        .background { Color.clear }
        .navigationTitle("Klangradar KI")
        .sheet(isPresented: $showsPlusPaywall) {
            PlusPaywallView(feature: .coach)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .navigationDestination(for: ConcertEvent.self) { event in
            EventDetailView(event: event, repository: eventRepository, contentRepository: contentRepository)
        }
        .sheet(isPresented: $showsCheckin) { CoachCheckinSheet(auth: auth, repository: repository) { await loadDashboard() } }
        .task { await loadDashboard() }
    }

    private var overview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                coachHeader
                Button { showsCheckin = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3").font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kurzer Check-in").font(.headline)
                            Text(dashboard?.latestCheckin == nil ? "Stimmung, Energie, Zeit und Budget angeben" : "Aktuellen Abendkontext anpassen")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }.padding(16).background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
                }.buttonStyle(.plain)

                if let dashboard {
                    Text("Deine KI-Einblicke").font(.title2.bold())
                    lensGrid(dashboard)
                    if dashboard.signalQuality == "low" {
                        Label("Ich lerne dich noch kennen. Empfehlungen basieren aktuell vor allem auf deinen bestätigten Interessen und gespeicherten Events.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary).padding(14).background(.thinMaterial, in: .rect(cornerRadius: 16))
                    }
                    if !dashboard.insights.isEmpty {
                        Text("Für dich jetzt").font(.title2.bold()).padding(.top, 4)
                        ForEach(dashboard.insights) { insight in insightCard(insight) }
                    }
                    if !dashboard.trends.isEmpty {
                        Text("Beobachtete Zusammenhänge").font(.title2.bold()).padding(.top, 4)
                        ForEach(Array(dashboard.trends.enumerated()), id: \.offset) { _, trend in trendCard(trend) }
                    }
                } else if isLoading { ProgressView("Deine Daten werden ausgewertet …").frame(maxWidth: .infinity).padding(40) }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }.padding().padding(.bottom, 80)
        }
        .refreshable { await loadDashboard() }
    }

    // Nutzerfeedback: "Design der KI in der nativen App mehr nach iOS,
    // aktuell sieht es noch etwas komisch aus" -- die violette
    // Farbverlauf-Karte mit weißem Text wirkte wie ein generisches
    // Chat-App-Template statt einem Klangradar-eigenen Bereich. Jetzt
    // Systemmaterial/-farben wie im Rest der App (siehe coachLens/
    // insightCard direkt darunter), Akzentfarbe nur noch fürs Icon.
    private var coachHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KlangradarTheme.accent)
                Text("Persönliche Kultur-KI")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            Text("Was passt heute zu dir?").font(.largeTitle.bold())
            Text("Ich verbinde deinen Geschmack, deine Planung und deinen aktuellen Check-in – mit echten Veranstaltungen aus Klangradar.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("KI fragen", systemImage: "bubble.left.and.bubble.right.fill") { withAnimation { selectedSection = .chat } }
                .buttonStyle(.borderedProminent)
                .tint(KlangradarTheme.accent)
        }.padding(20)
            .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func lensGrid(_ value: CoachDashboard) -> some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
            coachLens("Passung", "heart.text.square.fill", "\(value.knownPreferences) Präferenzen", "\(value.recentIntentSignals) starke aktuelle Signale")
            coachLens("Kulturrhythmus", "calendar.badge.clock", "\(value.plannedEvents) geplant", "\(value.reflectedVisits) Besuche reflektiert")
            coachLens("Entdeckung", "safari.fill", "\(value.recentViews) Ansichten", value.topGenres.isEmpty ? "Noch offen" : value.topGenres.prefix(2).joined(separator: " · "))
            coachLens("Datengrundlage", "chart.bar.doc.horizontal.fill", value.signalQuality == "high" ? "Aussagekräftig" : value.signalQuality == "medium" ? "Im Aufbau" : "Lernphase", "Jede Aussage bleibt prüfbar")
        }
    }

    private func coachLens(_ title: String, _ icon: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(KlangradarTheme.accent)
            Text(title).font(.headline)
            Text(value).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, minHeight: 118, alignment: .leading).padding(15)
            .background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func insightCard(_ insight: CoachInsight) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Image(systemName: insightIcon(insight.kind)).foregroundStyle(insight.priority >= 3 ? .orange : KlangradarTheme.accent); Text(insight.title).font(.headline); Spacer() }
            Text(insight.body).font(.subheadline).foregroundStyle(.secondary)
            if let action = insight.actions.first, action.string("type") == "ask_coach", let prompt = action.string("prompt") {
                Button("Mit der KI planen") { draft = prompt; selectedSection = .chat; sendTask = Task { await send() } }.buttonStyle(.bordered)
            }
        }.padding(16).background(.thinMaterial, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func trendCard(_ trend: JSONObject) -> some View {
        let sample = trend.integer("sample_size") ?? 0
        let rating = trend.number("avg_rating")
        let energy = trend.number("avg_energy_change")
        return VStack(alignment: .leading, spacing: 6) {
            Text((trend.string("value") ?? "Muster").capitalized).font(.headline)
            Text([rating.map { "Ø Bewertung \($0.formatted(.number.precision(.fractionLength(1))))/5" }, energy.map { "Energieveränderung \($0 >= 0 ? "+" : "")\($0.formatted(.number.precision(.fractionLength(1))))" }].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
            Text("Zusammenhang aus \(sample) Reflexionen – keine Kausalitätsaussage.").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.thinMaterial, in: .rect(cornerRadius: 18))
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 13) {
                    // Redesign: Willkommensbildschirm statt Starttext-Blase.
                    if messages.count <= 1 && !isSending {
                        CoachWelcome(prompts: suggestedPrompts, context: context) { prompt in sendTask = Task { await send(prompt) } }
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    } else {
                        ForEach(messages.dropFirst()) { message in
                            CoachMessageRow(text: message.text, isUser: message.user, animate: message.id == messages.last?.id && !message.user) {
                                if !message.events.isEmpty { eventCarousel(message.events, isAlternatives: message.eventsAreAlternatives) }
                            }
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        }
                    }
                    // Statt Spinner: springende Punkte mit wechselndem Status.
                    if isSending {
                        CoachTypingIndicator()
                            .id("coach-loading")
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .accessibilityLabel("Klangradar KI lädt die Antwort")
                    }
                    if let proposal = memoryProposal { proposalCard("Soll ich mir das merken?", proposal, action: "confirm_memory") }
                    if let proposal = goalProposal { proposalCard("Dieses Ziel übernehmen?", proposal, action: "confirm_goal") }
                    if let errorMessage {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(errorMessage).font(.subheadline)
                                if let retryDraft {
                                    Button("Erneut versuchen") {
                                        draft = retryDraft
                                        sendTask = Task { await send() }
                                    }
                                    .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 16, style: .continuous))
                    }
                    Color.clear.frame(height: 1).id("coach-bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, presentsChatDirectly ? 8 : 12)
                .padding(.bottom, 12)
            }
            // 14.11.2026 (Redesign): Eingabe wie in Nachrichten – feste Leiste
            // mit Material, Vorschläge als kleine Chips darüber, nichts scheint
            // mehr durch; Senden-Knopf im Eingabefeld.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !suggestedPrompts.isEmpty && messages.count > 1 && !isSending {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedPrompts, id: \.self) { prompt in
                                    Button { sendTask = Task { await send(prompt) } } label: {
                                        Text(prompt)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(KlangradarTheme.accent)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(KlangradarTheme.accent.opacity(0.1), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    if PlusStore.shared.enforcesLimits {
                        Button { showsPlusPaywall = true } label: {
                            HStack(spacing: 6) {
                                Text(CoachQuota.remaining == 0 ? "Diese Woche keine Fragen mehr frei" : "Noch \(CoachQuota.remaining) von \(CoachQuota.weeklyLimit) Fragen diese Woche")
                                    .foregroundStyle(.secondary)
                                Text("· Mit Plus unbegrenzt").foregroundStyle(KlangradarTheme.accent)
                                PlusBadge()
                            }
                            .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Frag mich etwas …", text: $draft, axis: .vertical)
                            .font(.body)
                            .lineLimit(1...5)
                            .submitLabel(.send)
                            .onSubmit { sendTask = Task { await send() } }
                            .padding(.leading, 16)
                            .padding(.vertical, 10)
                        Button {
                            if isSending { sendTask?.cancel() } else { sendTask = Task { await send() } }
                        } label: {
                            Image(systemName: isSending ? "stop.fill" : "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(KlangradarTheme.accent, in: Circle())
                        }
                        .buttonStyle(CoachSendButtonStyle())
                        .accessibilityLabel(isSending ? "Antwort stoppen" : "Nachricht senden")
                        .disabled(!isSending && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .padding(.trailing, 5)
                        .padding(.bottom, 5)
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 21, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.5) }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .padding(.top, 8)
                .background(.bar)
            }
            .animation(.spring(duration: 0.45, bounce: 0.25), value: messages.count)
            .animation(.spring(duration: 0.35), value: isSending)
            .background(Color(uiColor: .systemGroupedBackground))
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("coach-bottom") } }
            .onChange(of: isSending) { _, sending in if sending { withAnimation { proxy.scrollTo("coach-bottom") } } }
        }
    }

    // Nutzerfeedback: statt einer einzelnen großen, textlastigen Karte pro
    // Event jetzt ein horizontal scrollbares Band aus kompakten Miniaturen
    // (max. 4) direkt unter der Antwort -- jede öffnet per Tap die volle
    // Detailansicht über dieselbe navigationDestination(for: ConcertEvent).
    /// 14.11.2026: Treffer als ruhige Liste (wie überall in der App) statt
    /// eines Karussells halb abgeschnittener Karten.
    private func eventCarousel(_ events: [CoachEvent], isAlternatives: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isAlternatives {
                Label("Keine exakte Übereinstimmung – Alternativen", systemImage: "arrow.triangle.branch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(events.prefix(4).enumerated()), id: \.element.id) { index, event in
                    NavigationLink(value: event.concertEvent) { coachEventRow(event) }
                        .buttonStyle(.plain)
                    if index < min(events.count, 4) - 1 { Divider().padding(.leading, 78) }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
        }
    }

    private func coachEventRow(_ event: CoachEvent) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: event.imageURL, maxPixel: 200) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Rectangle().fill(KlangradarTheme.accent.opacity(0.12)).overlay { Image(systemName: "music.note").foregroundStyle(KlangradarTheme.accent) } }
            }
            .frame(width: 54, height: 54)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text([event.startDate.map { KlangradarDateTime.string($0, format: "EEE, d. MMM · HH:mm") }, event.venueName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { Task { await favorites.toggle(event.id) } } label: {
                Image(systemName: favorites.ids.contains(event.id) ? "heart.fill" : "heart")
                    .foregroundStyle(favorites.ids.contains(event.id) ? Color.red : Color.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favorites.ids.contains(event.id) ? "Von Favoriten entfernen" : "Merken")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func proposalCard(_ title: String, _ proposal: JSONObject, action: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline); Text(proposal.string("label") ?? proposal.string("title") ?? "Persönliche Einstellung").font(.subheadline).foregroundStyle(.secondary)
            HStack { Button("Übernehmen") { Task { await confirm(proposal, action: action) } }.buttonStyle(.borderedProminent); Button("Nicht jetzt") { if action == "confirm_memory" { memoryProposal = nil } else { goalProposal = nil } }.buttonStyle(.bordered) }
        }.padding(15).background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 18))
    }

    @MainActor private func loadDashboard() async {
        guard let repository, let token = auth.accessToken else { errorMessage = "Bitte melde dich an, damit die Klangradar KI deine Daten sicher verwenden kann."; return }
        isLoading = true; defer { isLoading = false }
        do { dashboard = try await repository.coachDashboard(token: token); errorMessage = nil } catch { errorMessage = coachErrorDescription(error) }
    }

    @MainActor private func send(_ prompt: String? = nil) async {
        let text = (prompt ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard let repository, let token = auth.accessToken else {
            errorMessage = "Bitte melde dich an, damit die Klangradar KI deine Daten sicher verwenden kann."
            return
        }
        if PlusStore.shared.enforcesLimits && CoachQuota.remaining == 0 {
            showsPlusPaywall = true
            return
        }
        draft = ""; retryDraft = text; isSending = true; errorMessage = nil; messages.append(.init(text: text, user: true)); memoryProposal = nil; goalProposal = nil
        defer { isSending = false }
        do {
            // Bereichs-Hinweis nur bei der ersten Frage eines Gesprächs.
            let outgoing = conversationID == nil ? [text, context.promptHint].compactMap { $0 }.joined(separator: "\n\n") : text
            let reply = try await repository.askCoach(message: outgoing, conversationID: conversationID, cityName: cityStore.selectedCity?.name, token: token)
            guard !Task.isCancelled else { return }
            conversationID = reply.conversationID
            messages.append(ChatMessage(text: reply.answer, user: false, events: reply.events, eventsAreAlternatives: reply.eventsAreAlternatives))
            Haptics.light()
            memoryProposal = reply.memoryProposal; goalProposal = reply.goalProposal; suggestedPrompts = reply.suggestedPrompts; retryDraft = nil
            if !PlusStore.shared.isPlus { CoachQuota.recordQuestion() }
        } catch is CancellationError {
            // Nutzer hat das Warten auf die Antwort abgebrochen (Stopp-Quadrat) -- keine Fehlermeldung.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = coachErrorDescription(error)
        }
    }

    @MainActor private func confirm(_ proposal: JSONObject, action: String) async {
        guard let repository, let token = auth.accessToken else { return }
        do { try await repository.confirmCoachProposal(proposal, kind: action, token: token); if action == "confirm_memory" { memoryProposal = nil } else { goalProposal = nil }; messages.append(.init(text: action == "confirm_memory" ? "Gespeichert. Du kannst diese Erinnerung jederzeit in Mein Klangradar ändern oder löschen." : "Ziel übernommen. Ich berücksichtige es künftig in Planung und Check-ins.", user: false)); await loadDashboard() } catch { errorMessage = coachErrorDescription(error) }
    }

    private func insightIcon(_ kind: String) -> String { switch kind { case "ticket": "ticket.fill"; case "goal": "target"; case "trend": "chart.line.uptrend.xyaxis"; case "reflection": "quote.bubble.fill"; case "discovery": "safari.fill"; default: "calendar.badge.clock" } }

    private func coachErrorDescription(_ error: Error) -> String {
        guard let apiError = error as? APIError else {
            return "Die Klangradar KI ist gerade nicht erreichbar. Prüfe deine Verbindung und versuche es erneut."
        }
        switch apiError {
        case .httpStatus(401, _):
            return "Deine Anmeldung ist abgelaufen. Melde dich bitte erneut an."
        case .httpStatus(404, _):
            return "Die Klangradar KI wird gerade aktualisiert. Bitte versuche es gleich noch einmal."
        case .httpStatus(let status, _) where status >= 500:
            return "Die Klangradar KI braucht gerade etwas länger. Bitte versuche es gleich noch einmal."
        default:
            return apiError.localizedDescription
        }
    }
}

struct CoachSendButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.3)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// Nutzerfeedback: "Überarbeitung von kurzer Check-in" -- die
// Stimmungsauswahl war eine horizontal scrollende Reihe winziger Kapseln,
// kaum als eigener Bereich erkennbar. Jetzt ein Raster großer Kacheln
// (Icon über Label), ein mittlerer Sheet-Detent mit Drag-Indikator statt
// einer vollen Seite -- näher an Apples eigenen kurzen Eingabe-Sheets
// (z. B. "Neue Erinnerung").
struct CoachCheckinSheet: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mood = "curious"
    @State private var energy = 3
    @State private var minutes = 150
    @State private var budget = 50.0
    @State private var companion = "alone"
    @State private var isSaving = false
    private let moods = [("calm","Ruhig","leaf"),("curious","Neugierig","sparkles"),("romantic","Romantisch","heart"),("social","Gesellig","person.2"),("adventurous","Abenteuerlustig","safari")]
    private let companions = [("alone","Allein","person"),("partner","Partner:in","person.2"),("friends","Freunde","person.3"),("family","Familie","figure.2.and.child.holdinghands"),("children","Kinder","figure.child")]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wie ist dir heute?").font(.headline)
                        LazyVGrid(columns: [.init(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                            ForEach(moods, id: \.0) { value, label, icon in
                                Button { withAnimation(.snappy(duration: 0.18)) { mood = value } } label: {
                                    VStack(spacing: 7) {
                                        Image(systemName: icon).font(.title2)
                                        Text(label).font(.caption.weight(.medium)).multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 74)
                                    .foregroundStyle(mood == value ? .white : .primary)
                                    .background(mood == value ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(.thinMaterial), in: .rect(cornerRadius: 16, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Energie").font(.headline); Spacer(); Text("\(energy)/5").foregroundStyle(.secondary) }
                        Picker("Energie", selection: $energy) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Rahmen").font(.headline)
                        VStack(spacing: 0) {
                            Stepper("Zeit: \(minutes) Min.", value: $minutes, in: 30...480, step: 30).padding(12)
                            Divider().padding(.leading, 12)
                            Stepper("Budget: \(Int(budget)) €", value: $budget, in: 0...500, step: 10).padding(12)
                        }
                        .background(.thinMaterial, in: .rect(cornerRadius: 16, style: .continuous))

                        LazyVGrid(columns: [.init(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                            ForEach(companions, id: \.0) { value, label, icon in
                                Button { companion = value } label: {
                                    VStack(spacing: 5) {
                                        Image(systemName: icon).font(.body)
                                        Text(label).font(.caption2.weight(.medium))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .foregroundStyle(companion == value ? .white : .primary)
                                    .background(companion == value ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(.thinMaterial), in: .rect(cornerRadius: 12, style: .continuous))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Kurzer Check-in").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(isSaving ? "Speichert …" : "Fertig") { Task { await save() } }.disabled(isSaving) } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @MainActor private func save() async { guard let repository, let token = auth.accessToken else { return }; isSaving = true; defer { isSaving = false }; do { try await repository.coachCheckin(mood: mood, energy: energy, minutes: minutes, budget: budget, companion: companion, token: token); await onSaved(); dismiss() } catch { } }
}



/// Leuchtender "Klang-Orb" als Gesicht der KI; atmet, schneller beim Nachdenken.
struct CoachOrb: View {
    var size: CGFloat = 34
    var isThinking = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [KlangradarTheme.accent, .purple, .pink, .orange, KlangradarTheme.accent], center: .center))
                .blur(radius: size * 0.08)
                .rotationEffect(.degrees(pulse ? 360 : 0))
            Circle().fill(.white.opacity(0.18)).padding(size * 0.18)
            Image(systemName: "sparkles").font(.scaled(size * 0.42, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .scaleEffect(pulse ? 1.06 : 0.96)
        .shadow(color: .purple.opacity(0.35), radius: size * 0.25)
        .onAppear {
            withAnimation(.easeInOut(duration: isThinking ? 0.8 : 2.4).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

/// Willkommensbildschirm: Orb, Begrüßung, große Vorschlagskarten.
struct CoachWelcome: View {
    let prompts: [String]
    var context: CoachContext = .home
    let onSelect: (String) -> Void

    // 08.11.2026 (Redesign „Konzertführer“): Kontextkarte, persönliche
    // Serifen-Überschrift, Vorschläge als Karten mit Rubrik, kein Orb.
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let title = context.title, context.kind != .home {
                HStack(spacing: 12) {
                    Image(systemName: context.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(red: 0.91, green: 0.77, blue: 0.42))
                        .frame(width: 48, height: 48)
                        .background(Color(red: 0.17, green: 0.16, blue: 0.2), in: .rect(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DU SCHAUST GERADE").font(.caption2.weight(.semibold)).tracking(1.2).foregroundStyle(KlangradarTheme.accent)
                        Text(title).font(.system(.headline, design: .serif)).lineLimit(2)
                        if let detail = context.detail, !detail.isEmpty {
                            Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(context.greeting)
                    .font(.system(.largeTitle, design: .serif).weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Ich antworte aus echten Spielplänen und deinem Konzerttagebuch – und sage dir, wenn ich etwas nicht weiß.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(prompts.prefix(4).enumerated()), id: \.offset) { index, prompt in
                    Button {
                        Haptics.light()
                        onSelect(prompt)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(context.rubric(at: index).uppercased())
                                .font(.caption2.weight(.semibold)).tracking(1.2)
                                .foregroundStyle(KlangradarTheme.accent)
                            Text(prompt).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                .multilineTextAlignment(.leading).lineLimit(3)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 14, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.07)) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Nachrichtenzeile: KI mit Orb und Schreibmaschinen-Effekt, Nutzer mit Verlauf.
struct CoachMessageRow<Attachment: View>: View {
    let text: String
    let isUser: Bool
    var animate = false
    @ViewBuilder var attachment: () -> Attachment

    // 08.11.2026: Frage dunkel rechts, Antwort als ruhiger Text über die
    // ganze Breite – wie ein Gespräch, nicht wie ein Chatbot.
    // 14.11.2026 (Redesign): Frage als Akzent-Blase rechts, Antwort mit
    // kleiner Absenderzeile und echter Formatierung (Listen, fett).
    var body: some View {
        if isUser {
            HStack {
                Spacer(minLength: 56)
                Text(text)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(KlangradarTheme.accent, in: .rect(cornerRadius: 19, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Klangradar KI", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KlangradarTheme.accent)
                TypewriterText(text: text, animate: animate)
                    .font(.body)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                attachment()
            }
            .padding(.vertical, 2)
        }
    }
}

/// Zeigt neue Antworten zügig Wort für Wort an (wirkt lebendiger und schneller).
struct TypewriterText: View {
    let text: String
    let animate: Bool
    @State private var visibleWords = Int.max

    var body: some View {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        let shown = words.prefix(visibleWords).joined(separator: " ")
        Text((try? AttributedString(markdown: shown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(shown))
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: text) {
                guard animate, words.count > 3 else { visibleWords = .max; return }
                visibleWords = 0
                for index in 1...words.count {
                    try? await Task.sleep(for: .milliseconds(28))
                    visibleWords = index
                }
            }
    }
}

/// Springende Punkte mit wechselndem Status statt Spinner.
struct CoachTypingIndicator: View {
    @State private var phase = 0
    @State private var bounce = false
    private let steps = ["Denke nach …", "Suche Antworten …", "Prüfe Spielpläne …", "Formuliere …"]

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle().fill(KlangradarTheme.accent.opacity(0.8)).frame(width: 7, height: 7)
                            .offset(y: bounce ? -4 : 2)
                            .animation(.easeInOut(duration: 0.45).repeatForever().delay(Double(index) * 0.15), value: bounce)
                    }
                }
                Text(steps[phase % steps.count])
                    .font(.subheadline).foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .id(phase)
                    .transition(.opacity)
            }
            .padding(.horizontal, 15).padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 19, style: .continuous))
            Spacer(minLength: 0)
        }
        .onAppear { bounce = true }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(.easeInOut(duration: 0.3)) { phase += 1 }
            }
        }
    }
}

/// Sanft bewegter Farbschimmer hinter dem Chat.
struct CoachAmbientBackground: View {
    var isThinking: Bool
    @State private var drift = false

    var body: some View {
        ZStack {
            Circle().fill(KlangradarTheme.accent.opacity(isThinking ? 0.28 : 0.16)).frame(width: 340).blur(radius: 90)
                .offset(x: drift ? 120 : -100, y: drift ? -220 : -140)
            Circle().fill(Color.purple.opacity(isThinking ? 0.24 : 0.12)).frame(width: 300).blur(radius: 90)
                .offset(x: drift ? -130 : 110, y: drift ? 160 : 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 1.2), value: isThinking)
        .onAppear { withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true } }
        .ignoresSafeArea()
    }
}
