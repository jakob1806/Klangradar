import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

// Freunde-Ausbau 28.10.2026 (Claude Code): QR-Code, Scanner, Verbunden-Ansicht,
// Freundesliste, "Wer war noch da?", "Ticket übrig" und "Privat hingehen".
// Navigation nur über closure-basierte NavigationLinks (kein
// navigationDestination, siehe FriendsView).

// MARK: - QR-Code

enum FriendQRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// QR-Code des Einladungslinks auf weißem Grund (scharf skaliert).
struct FriendQRCodeImage: View {
    let code: String

    var body: some View {
        Group {
            if let image = FriendQRCode.image(for: FriendInvite.link(code: code).absoluteString) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("QR-Code mit deinem Freundescode \(code)")
    }
}

/// Großer QR-Code zum Vorzeigen.
struct FriendQRSheet: View {
    let code: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Text("Lass deinen Freund diesen Code scannen").font(.system(.title3, design: .serif).weight(.semibold)).multilineTextAlignment(.center)
            FriendQRCodeImage(code: code)
                .padding(18)
                .background(.white, in: .rect(cornerRadius: 24, style: .continuous))
                .frame(maxWidth: 300)
            Text(code).font(.system(.title2, design: .monospaced).weight(.semibold))
            Text("Mit der Kamera-App öffnet sich Klangradar direkt. In Klangradar: Freunde → „Code scannen“.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
    }
}

// MARK: - Code scannen

struct FriendCodeScannerView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed: Bool?
    @State private var showsInvalidHint = false
    @State private var didFinish = false

    private var scannerAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        Group {
            if cameraAllowed == nil {
                ProgressView()
            } else if cameraAllowed == true && scannerAvailable {
                QRDataScanner { payload in handle(payload) }
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text(showsInvalidHint ? "Das ist kein Klangradar-Freundescode." : "Halte die Kamera auf den QR-Code deines Freundes.")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.regularMaterial, in: .capsule)
                            .padding(.bottom, 40)
                    }
            } else {
                ContentUnavailableView {
                    Label("Kamera nicht verfügbar", systemImage: "camera")
                } description: {
                    Text(cameraAllowed == false
                         ? "Erlaube den Kamerazugriff in den Einstellungen oder gib den Code von Hand ein."
                         : "Auf diesem Gerät kann Klangradar keine Codes scannen. Gib den Code von Hand ein.")
                } actions: {
                    if cameraAllowed == false {
                        Button("Einstellungen öffnen") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Code scannen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        .task {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: cameraAllowed = true
            case .notDetermined: cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
            default: cameraAllowed = false
            }
        }
    }

    private func handle(_ payload: String) {
        guard !didFinish else { return }
        guard let code = FriendCodeParser.code(from: payload) else { showsInvalidHint = true; return }
        didFinish = true
        Haptics.confirm()
        dismiss()
        onCode(code)
    }
}

private struct QRDataScanner: UIViewControllerRepresentable {
    let onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Void
        init(onPayload: @escaping (String) -> Void) { self.onPayload = onPayload }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    onPayload(payload)
                    return
                }
            }
        }
    }
}

// MARK: - Ihr seid jetzt verbunden

/// Nach dem Annehmen einer Anfrage, nach Code/QR und nach dem
/// Einladungslink: gemeinsame Konzerte und "Gemeinsam planen".
struct FriendConnectedSheet: View {
    let connection: FriendConnection
    var viaInvite = false

    @Environment(\.dismiss) private var dismiss
    @State private var planEvent: ConcertEvent?
    @State private var loadingPlan: UUID?

    private var firstName: String { connection.person.name.split(separator: " ").first.map(String.init) ?? connection.person.name }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if !connection.shared.isEmpty {
                    eventCard("Habt ihr beide gemerkt", caption: "Plant den Abend gemeinsam: Zusagen, Treffpunkt, Uhrzeit.", events: connection.shared) { event in
                        AnyView(planButton(event))
                    }
                }
                if !connection.upcoming.isEmpty {
                    eventCard("\(firstName) geht demnächst zu", caption: nil, events: connection.upcoming) { event in
                        AnyView(JoinFriendButton(event: event, friend: connection.person))
                    }
                }
                if connection.shared.isEmpty && connection.upcoming.isEmpty {
                    Label("Noch keine gemeinsamen Konzerte. Öffne ein Konzert und tippe auf „Mit Freunden planen“.", systemImage: "music.note")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.horizontal, KlangradarTheme.pagePadding)
                }
                NavigationLink { UserProfileView(userID: connection.person.id) } label: {
                    Label("Profil von \(firstName) ansehen", systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.bordered)
                .tint(KlangradarTheme.accent)
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
            .padding(.vertical, 20)
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        .sheet(item: $planEvent) { event in
            NavigationStack { PlanComposerView(event: event, preselected: [connection.person.id]) }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            SocialAvatar(name: connection.person.name, url: connection.person.avatarURL, size: 96)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, KlangradarTheme.accent)
                        .background(Circle().fill(Color(uiColor: .systemBackground)).padding(2))
                }
            Text(viaInvite ? "Du bist jetzt mit \(firstName) verbunden" : "Ihr seid jetzt verbunden")
                .font(.system(.title2, design: .serif).weight(.semibold))
                .multilineTextAlignment(.center)
            Text(viaInvite ? "Ihr seht gegenseitig, zu welchen Konzerten ihr geht, und könnt Abende gemeinsam planen." : "Du und \(firstName) seht jetzt, zu welchen Konzerten ihr geht.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let match = connection.tasteMatch {
                Label("\(match) % Geschmacks-Match", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(KlangradarTheme.accent)
                    .background(KlangradarTheme.accent.opacity(0.12), in: .capsule)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, KlangradarTheme.pagePadding)
    }

    private func eventCard(_ title: String, caption: String?, events: [SocialEvent], trailing: @escaping (SocialEvent) -> AnyView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.title3, design: .serif).weight(.semibold))
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)
            VStack(spacing: 0) {
                ForEach(events) { event in
                    SocialEventRow(event: event, trailing: trailing(event))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    if event.id != events.last?.id { Divider().padding(.leading, 82) }
                }
            }
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, KlangradarTheme.pagePadding)
        }
    }

    private func planButton(_ event: SocialEvent) -> some View {
        Button {
            Task {
                loadingPlan = event.id
                planEvent = await SocialStore.shared.concertEvent(event.id)
                loadingPlan = nil
            }
        } label: {
            Group {
                if loadingPlan == event.id { ProgressView().controlSize(.small) }
                else { Label("Gemeinsam planen", systemImage: "calendar.badge.plus") }
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(KlangradarTheme.accent)
            .background(KlangradarTheme.accent.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(loadingPlan != nil)
    }
}

// MARK: - Alle Freunde

struct FriendListView: View {
    var onChange: (() -> Void)? = nil

    @State private var friends: [Friend] = []
    @State private var query = ""
    @State private var sort: FriendSort = .nextConcert
    @State private var isLoading = true

    enum FriendSort: String, CaseIterable, Identifiable {
        case nextConcert = "Nächstes Konzert"
        case lastActive = "Zuletzt aktiv"
        case name = "Name"
        var id: String { rawValue }
    }

    private var filtered: [Friend] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matching = trimmed.isEmpty ? friends : friends.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        return matching.sorted(by: order)
    }

    private func order(_ lhs: Friend, _ rhs: Friend) -> Bool {
        switch sort {
        case .nextConcert:
            if lhs.nextConcert != rhs.nextConcert { return (lhs.nextConcert ?? .distantFuture) < (rhs.nextConcert ?? .distantFuture) }
        case .lastActive:
            if lhs.lastActive != rhs.lastActive { return (lhs.lastActive ?? .distantPast) > (rhs.lastActive ?? .distantPast) }
        case .name:
            break
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    var body: some View {
        let close = filtered.filter(\.isClose)
        let others = filtered.filter { !$0.isClose }
        List {
            if !close.isEmpty {
                Section {
                    ForEach(close) { row($0) }
                } header: {
                    Text("Enge Freunde")
                } footer: {
                    Text("Enge Freunde stehen in deinem Freundeskreis ganz vorn.")
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { row($0) }
                } header: {
                    if !close.isEmpty { Text("Alle Freunde") }
                }
            }
        }
        .overlay {
            if isLoading && friends.isEmpty {
                ProgressView()
            } else if friends.isEmpty {
                ContentUnavailableView("Noch keine Freunde", systemImage: "person.2", description: Text("Lade Freunde mit deinem Code oder Link ein."))
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Freunde durchsuchen")
        .navigationTitle("Deine Freunde")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sortieren nach", selection: $sort) {
                        ForEach(FriendSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sortieren")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ friend: Friend) -> some View {
        NavigationLink {
            UserProfileView(userID: friend.id)
        } label: {
            HStack(spacing: 12) {
                SocialAvatar(name: friend.name, url: friend.avatarURL, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(friend.name).font(.headline)
                        if friend.isMuted {
                            Image(systemName: "bell.slash.fill").font(.caption).foregroundStyle(.secondary).accessibilityLabel("Stummgeschaltet")
                        }
                    }
                    if let subtitle = subtitle(friend) {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Task { await toggleClose(friend) }
                } label: {
                    Image(systemName: friend.isClose ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(friend.isClose ? Color.orange : Color.secondary.opacity(0.6))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(friend.isClose ? "Aus engen Freunden entfernen" : "Zu engen Freunden hinzufügen")
            }
        }
    }

    private func subtitle(_ friend: Friend) -> String? {
        switch sort {
        case .lastActive:
            if let active = friend.lastActive { return "Aktiv \(active.socialRelative)" }
        default:
            break
        }
        if let next = friend.nextConcert { return "Nächstes Konzert: \(KlangradarDateTime.string(next, format: "EE d. MMM"))" }
        if let active = friend.lastActive { return "Aktiv \(active.socialRelative)" }
        return nil
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { isLoading = false; return }
        friends = (try? await repository.friends(token: token)) ?? friends
        isLoading = false
    }

    private func toggleClose(_ friend: Friend) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token,
              let index = friends.firstIndex(where: { $0.id == friend.id }) else { return }
        let newValue = !friend.isClose
        Haptics.light()
        withAnimation(.snappy) { friends[index].isClose = newValue }
        do {
            try await repository.setCloseFriend(friend.id, close: newValue, token: token)
            onChange?()
        } catch {
            if let index = friends.firstIndex(where: { $0.id == friend.id }) { friends[index].isClose = !newValue }
        }
    }
}

// MARK: - Wer war noch da?

struct ConcertCompanionRow: View {
    let companion: ConcertCompanion

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink { UserProfileView(userID: companion.person.id) } label: {
                HStack(spacing: 12) {
                    SocialAvatar(name: companion.person.name, url: companion.person.avatarURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(companion.person.name).font(.headline).foregroundStyle(.primary)
                        if let detail = companion.person.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            RelationButton(person: companion.person, source: "concert", eventID: companion.event.id)
        }
    }
}

/// Freunde-Bereich: öffentliche Profile vom selben Konzert der letzten Tage.
struct ConcertCompanionsSection: View {
    let reloadToken: Int
    @State private var companions: [ConcertCompanion] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !companions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wer war noch da?").font(.system(.title2, design: .serif).weight(.semibold))
                    Text("Öffentliche Profile, die mit dir im selben Konzert waren").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
                VStack(spacing: 0) {
                    ForEach(companions.prefix(5)) { companion in
                        ConcertCompanionRow(companion: companion).padding(14)
                        if companion.id != companions.prefix(5).last?.id { Divider().padding(.leading, 70) }
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
        }
        .task(id: reloadToken) {
            guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
            companions = (try? await repository.concertCompanions(token: token)) ?? []
        }
    }
}

// MARK: - Ticket übrig

/// Ein Angebot: von Freunden ("Nehme ich") oder eigenes ("Zurückziehen").
struct TicketOfferRow: View {
    let offer: TicketOffer
    var showsEvent = true
    let onChange: () async -> Void

    @State private var isWorking = false
    @State private var message: String?

    private var firstName: String { offer.person.name.split(separator: " ").first.map(String.init) ?? offer.person.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsEvent { SocialEventRow(event: offer.event) }
            HStack(alignment: .top, spacing: 10) {
                if offer.mine {
                    Image(systemName: "ticket.fill").font(.title3).foregroundStyle(KlangradarTheme.accent).frame(width: 30)
                } else {
                    SocialAvatar(name: offer.person.name, url: offer.person.avatarURL, size: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.subheadline.weight(.semibold))
                    if let note = offer.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    if let message { Text(message).font(.caption).foregroundStyle(KlangradarTheme.accent) }
                }
                Spacer(minLength: 0)
                action
            }
        }
    }

    private var headline: String {
        if offer.mine {
            return offer.isOpen ? "Du bietest ein Ticket an" : "Dein Ticket geht an \(offer.takenByName ?? "eine:n Freund:in")"
        }
        return offer.takenByMe ? "Das Ticket von \(firstName) gehört dir" : "\(firstName) hat ein Ticket übrig"
    }

    @ViewBuilder private var action: some View {
        if offer.mine && offer.isOpen {
            Button("Zurückziehen") { Task { await withdraw() } }
                .buttonStyle(.bordered).tint(.secondary).controlSize(.small).disabled(isWorking)
        } else if !offer.mine && offer.isOpen {
            Button("Nehme ich") { Task { await claim() } }
                .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent).controlSize(.small).disabled(isWorking)
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(KlangradarTheme.accent)
        }
    }

    private func claim() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isWorking = true
        defer { isWorking = false }
        switch (try? await repository.claimTicketOffer(offer.id, token: token)) ?? "not_allowed" {
        case "ok":
            Haptics.confirm()
            message = "\(firstName) bekommt Bescheid. Klärt die Übergabe direkt miteinander."
        case "taken":
            message = "Da war leider jemand schneller."
        default:
            message = "Das hat nicht geklappt."
        }
        try? await Task.sleep(for: .seconds(2))
        await onChange()
    }

    private func withdraw() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isWorking = true
        defer { isWorking = false }
        try? await repository.withdrawTicketOffer(offer.id, token: token)
        Haptics.soft()
        await onChange()
    }
}

struct TicketOffersSection: View {
    let reloadToken: Int
    @State private var offers: [TicketOffer] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !offers.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ticket übrig").font(.system(.title2, design: .serif).weight(.semibold))
                    Text("Wer zuerst zusagt, bekommt es").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
                VStack(spacing: 0) {
                    ForEach(offers) { offer in
                        TicketOfferRow(offer: offer) { await load() }.padding(14)
                        if offer.id != offers.last?.id { Divider().padding(.leading, 14) }
                    }
                }
                .background(KlangradarTheme.accent.opacity(0.08), in: .rect(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
        }
        .task(id: reloadToken) { await load() }
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        offers = (try? await repository.ticketOffers(token: token)) ?? []
    }
}

struct TicketOfferComposer: View {
    let event: ConcertEvent
    let onSent: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var isSending = false
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                Text(event.title).font(.headline)
                Text(event.dateLine).font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                TextField("z. B. Parkett, Reihe 5 · 35 €", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .onChange(of: note) { _, value in if value.count > 200 { note = String(value.prefix(200)) } }
            } header: {
                Text("Hinweis (optional)")
            } footer: {
                Text("Deine Freunde bekommen Bescheid. Wer zuerst zusagt, bekommt das Ticket, das Angebot schließt sich dann. Übergabe und Bezahlung klärt ihr direkt miteinander.")
            }
            if failed {
                Section { Text("Das Angebot konnte nicht gesendet werden.").foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Ticket anbieten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Anbieten") { Task { await send() } }.fontWeight(.semibold).disabled(isSending)
            }
        }
    }

    private func send() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isSending = true
        defer { isSending = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await repository.offerTicket(eventID: event.id, note: trimmed.isEmpty ? nil : trimmed, token: token)
            Haptics.confirm()
            await onSent()
            dismiss()
        } catch {
            failed = true
        }
    }
}

// MARK: - Konzertseite: Ticket übrig und Privat hingehen

struct EventFriendsExtras: View {
    let event: ConcertEvent
    @EnvironmentObject private var favorites: FavoriteStore
    @State private var state: EventSocialState?
    @State private var showsOfferComposer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let state {
                ForEach(state.friendOffers) { offer in
                    TicketOfferRow(offer: offer, showsEvent: false) { await load() }
                        .padding(14)
                        .background(KlangradarTheme.accent.opacity(0.08), in: .rect(cornerRadius: 18, style: .continuous))
                }
                if state.myStatus != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        if let mine = state.myOffer {
                            TicketOfferRow(offer: mine, showsEvent: false) { await load() }
                        } else {
                            Button { showsOfferComposer = true } label: {
                                Label("Ticket übrig? Freunden anbieten", systemImage: "ticket")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(KlangradarTheme.accent)
                        }
                        Divider()
                        Toggle(isOn: privateBinding) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("Privat hingehen", systemImage: "eye.slash").font(.subheadline.weight(.semibold))
                                Text("Freunde sehen nicht, dass du dir dieses Konzert gemerkt hast.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(KlangradarTheme.accent)
                    }
                    .padding(14)
                    .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(.bottom, hasContent ? 20 : 0)
        .task(id: favorites.ids.contains(event.id)) { await load() }
        .sheet(isPresented: $showsOfferComposer) {
            NavigationStack { TicketOfferComposer(event: event) { await load() } }
                .presentationDetents([.medium, .large])
        }
    }

    private var hasContent: Bool {
        guard let state else { return false }
        return !state.friendOffers.isEmpty || state.myStatus != nil
    }

    private var privateBinding: Binding<Bool> {
        Binding(
            get: { state?.isPrivate ?? false },
            set: { newValue in
                state?.isPrivate = newValue
                Haptics.light()
                Task {
                    guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
                    do { try await repository.setConcertPrivate(eventID: event.id, isPrivate: newValue, token: token) }
                    catch { state?.isPrivate = !newValue }
                }
            }
        )
    }

    private func load() async {
        guard (event.startDate ?? .distantPast) > .now,
              let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        state = try? await repository.eventSocialState(eventID: event.id, token: token)
    }
}
