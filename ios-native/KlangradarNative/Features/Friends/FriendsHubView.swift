import SwiftUI

/// Einladungslink: https-Link (öffnet App bzw. Webseite mit Code) plus Code als Text.
enum FriendInvite {
    static func link(code: String) -> URL { URL(string: "https://klangradar.com/f/\(code)")! }

    static func message(code: String) -> String {
        "Lass uns auf Klangradar sehen, zu welchen Konzerten wir gehen 🎻\n\(link(code: code).absoluteString)\nMein Freundescode: \(code)"
    }
}

enum FriendsHubTab: String, CaseIterable, Identifiable {
    case activity = "Aktivität"
    case plans = "Pläne"
    case friends = "Freunde"
    var id: String { rawValue }
}

/// Freunde-Bereich: Aktivität, Konzertpläne, Freunde & Anfragen.
/// Profile und Pläne werden direkt verlinkt (NavigationLink mit Ziel), nicht
/// über navigationDestination: FriendsView liegt mal als Unterseite im
/// Profil-Stapel, mal in einem eigenen Sheet. Als Unterseite registrierte
/// Ziele schoben Profile doppelt auf (Nutzermeldung 27.10.2026: "Endlosschleife,
/// erst nach Zurück kommt das Profil").
struct FriendsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    var initialTab: FriendsHubTab = .activity

    @ObservedObject private var deepLinks = DeepLinkRouter.shared
    @ObservedObject private var social = SocialStore.shared
    @State private var tab: FriendsHubTab = .activity
    @State private var code: String?
    @State private var friends: [Friend] = []
    @State private var requests: [FriendRequest] = []
    @State private var activity: [ActivityItem] = []
    @State private var plans: [ConcertPlan] = []
    @State private var isLoading = true
    @State private var message: String?
    @State private var codeInput = ""
    @State private var showsFindFriends = false
    @State private var showsSettings = false
    /// Lädt die Social-Abschnitte (Nachklang, Buddys, Gruppen) mit neu.
    @State private var reloadToken = 0

    var body: some View {
        Group {
            if auth.userID == nil {
                ContentUnavailableView {
                    Label("Gemeinsam ins Konzert", systemImage: "person.2.wave.2")
                } description: {
                    Text("Melde dich an, um Freunde hinzuzufügen, Konzertabende zu planen und zu sehen, wohin deine Freunde gehen.")
                }
            } else {
                hub
            }
        }
        .navigationTitle("Freunde")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if auth.userID != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Freunde finden", systemImage: "person.badge.plus") { showsFindFriends = true }
                        if let code { ShareLink(item: FriendInvite.message(code: code)) { Label("Einladungslink teilen", systemImage: "link") } }
                        Button("Privatsphäre & Profil", systemImage: "hand.raised") { showsSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showsFindFriends, onDismiss: { Task { await load() } }) {
            NavigationStack { FindFriendsView(code: code) }
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack { SocialSettingsView() }
        }
        .task {
            tab = initialTab
            await load()
        }
        .onChange(of: deepLinks.pendingFriendCode) { _, value in
            guard let value else { return }
            deepLinks.pendingFriendCode = nil
            Task { await add(value) }
        }
    }

    /// Seit 23.10.2026 (Nutzerwunsch: "zu linear, wie viele Sachen unter
    /// Profil") keine Liste mit Segmenten mehr, sondern eine durchlaufende
    /// Seite wie ein Konzertprogramm: Freundeskreis, gemeinsame Abende als
    /// Plakate, wohin Freunde gehen, Nachklang (Bewertungen), Code als
    /// Eintrittskarte. `initialTab` springt zum passenden Abschnitt.
    private var hub: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    circleSection
                    if !incomingRequests.isEmpty { requestsSection }
                    plansSection.id(FriendsHubTab.plans)
                    BuddySection(reloadToken: reloadToken)
                    goingSection.id(FriendsHubTab.activity)
                    GroupsSection(reloadToken: reloadToken)
                    EchoSection(reloadToken: reloadToken)
                    ticketSection.id(FriendsHubTab.friends)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: KlangradarTheme.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await load() }
            .onChange(of: isLoading) { _, loading in
                guard !loading, tab != .activity else { return }
                withAnimation(.snappy) { proxy.scrollTo(tab, anchor: .top) }
            }
        }
    }

    private var incomingRequests: [FriendRequest] { requests.filter(\.incoming) }

    /// Freunde, die zum selben Konzert gehen, auf einem Plakat zusammengefasst.
    private var goingGroups: [FriendsGoingGroup] {
        var order: [UUID] = []
        var groups: [UUID: FriendsGoingGroup] = [:]
        for item in activity where item.kind == .attending {
            if groups[item.event.id] == nil {
                order.append(item.event.id)
                groups[item.event.id] = FriendsGoingGroup(event: item.event, people: [])
            }
            if !(groups[item.event.id]?.people.contains(item.person) ?? true) {
                groups[item.event.id]?.people.append(item.person)
            }
        }
        return order.compactMap { groups[$0] }
            .sorted { ($0.event.start ?? .distantFuture) < ($1.event.start ?? .distantFuture) }
    }

    private func sectionTitle(_ title: String, _ caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(.title2, design: .serif).weight(.semibold))
            if let caption { Text(caption).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, KlangradarTheme.pagePadding)
    }

    // MARK: Freundeskreis

    private var circleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(friends.isEmpty ? "Konzerte sind schöner zu zweit" : "Dein Freundeskreis")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                Text(circleCaption).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    Button { showsFindFriends = true } label: {
                        FriendCircleTile(title: "Einladen") {
                            Circle()
                                .strokeBorder(KlangradarTheme.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .overlay { Image(systemName: "plus").font(.title2.weight(.medium)).foregroundStyle(KlangradarTheme.accent) }
                        }
                    }
                    .buttonStyle(.plain)
                    ForEach(friends) { friend in
                        NavigationLink { UserProfileView(userID: friend.id) } label: {
                            FriendCircleTile(title: friend.name.split(separator: " ").first.map(String.init) ?? friend.name, badge: friend.upcomingCount > 0 ? "\(friend.upcomingCount)" : nil) {
                                SocialAvatar(name: friend.name, url: friend.avatarURL, size: 68)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
        }
    }

    private var circleCaption: String {
        if friends.isEmpty { return "Lade Freunde ein, plant Abende gemeinsam und seht, wohin sie gehen." }
        let busy = friends.filter { $0.upcomingCount > 0 }.count
        let base = "\(friends.count) \(friends.count == 1 ? "Freund:in" : "Freunde")"
        return busy == 0 ? base : "\(base) · \(busy) mit Konzertplänen"
    }

    // MARK: Anfragen

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Möchten dich hinzufügen")
            VStack(spacing: 0) {
                ForEach(incomingRequests) { request in
                    HStack(spacing: 12) {
                        NavigationLink { UserProfileView(userID: request.person.id) } label: {
                            HStack(spacing: 12) {
                                SocialAvatar(name: request.person.name, url: request.person.avatarURL, size: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.person.name).font(.headline).foregroundStyle(.primary)
                                    if request.mutualFriends > 0 {
                                        Text("\(request.mutualFriends) gemeinsame \(request.mutualFriends == 1 ? "Freund:in" : "Freunde")").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        Button { Task { await respond(request, accept: false) } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.bordered).tint(.secondary).buttonBorderShape(.circle)
                            .accessibilityLabel("Ablehnen")
                        Button { Task { await respond(request, accept: true) } } label: { Image(systemName: "checkmark") }
                            .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent).buttonBorderShape(.circle)
                            .accessibilityLabel("Annehmen")
                    }
                    .padding(14)
                    if request.id != incomingRequests.last?.id { Divider().padding(.leading, 72) }
                }
            }
            .background(KlangradarTheme.accent.opacity(0.08), in: .rect(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, KlangradarTheme.pagePadding)
        }
    }

    // MARK: Gemeinsame Abende

    private var sortedPlans: [ConcertPlan] {
        plans.sorted { lhs, rhs in
            if (lhs.myStatus == "invited") != (rhs.myStatus == "invited") { return lhs.myStatus == "invited" }
            return (lhs.event.start ?? .distantFuture) < (rhs.event.start ?? .distantFuture)
        }
    }

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Gemeinsame Abende", plans.isEmpty ? nil : planCaption)
            if plans.isEmpty && !isLoading {
                EmptyStageCard(
                    symbol: "ticket",
                    title: "Noch nichts geplant",
                    text: "Öffne ein Konzert und tippe auf „Mit Freunden planen“. Ihr sagt zu, vereinbart Treffpunkt und Uhrzeit."
                )
                .padding(.horizontal, KlangradarTheme.pagePadding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(sortedPlans) { plan in
                            NavigationLink { PlanDetailView(planID: plan.id) { await load() } } label: { PlanPosterCard(plan: plan) }
                                .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, KlangradarTheme.pagePadding)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private var planCaption: String {
        let invites = plans.filter { $0.myStatus == "invited" }.count
        return invites > 0 ? "\(invites) \(invites == 1 ? "Einladung wartet" : "Einladungen warten") auf deine Antwort" : "Eure nächsten Konzertabende"
    }

    // MARK: Wohin Freunde gehen

    private var goingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Da gehen deine Freunde hin")
            let groups = goingGroups
            if groups.isEmpty && !isLoading {
                EmptyStageCard(
                    symbol: "music.note.house",
                    title: "Noch ruhig hier",
                    text: friends.isEmpty ? "Sobald du Freunde hast, siehst du hier, zu welchen Konzerten sie gehen." : "Deine Freunde haben gerade keine Konzerte vorgemerkt."
                )
                .padding(.horizontal, KlangradarTheme.pagePadding)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 18) {
                    ForEach(groups) { group in FriendsGoingPoster(group: group) }
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
            }
        }
    }

    // MARK: Code

    private var ticketSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Per Code verbinden")
            FriendCodeTicket(code: code)
                .padding(.horizontal, KlangradarTheme.pagePadding)
            HStack(spacing: 10) {
                TextField("Code eines Freundes", text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Color(uiColor: .secondarySystemBackground), in: .capsule)
                Button("Hinzufügen") { Task { await add(codeInput) } }
                    .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent)
                    .disabled(codeInput.trimmingCharacters(in: .whitespaces).count < 6)
            }
            .padding(.horizontal, KlangradarTheme.pagePadding)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, KlangradarTheme.pagePadding)
            }
            let outgoing = requests.filter { !$0.incoming }
            if !outgoing.isEmpty {
                Text("Gesendet an \(AvatarStack.names(outgoing.map(\.person)))")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal, KlangradarTheme.pagePadding)
            }
        }
    }

    // MARK: Laden & Aktionen

    private func load() async {
        guard let repository, let token = auth.accessToken else { isLoading = false; return }
        async let codeValue = try? repository.myFriendCode(token: token)
        async let friendRows = try? repository.friends(token: token)
        async let requestRows = try? repository.friendRequests(token: token)
        async let activityRows = try? repository.friendActivity(token: token)
        async let planRows = try? repository.concertPlans(token: token)
        code = await codeValue
        friends = await friendRows ?? []
        requests = await requestRows ?? []
        activity = await activityRows ?? []
        plans = await planRows ?? []
        isLoading = false
        reloadToken += 1
        await SocialStore.shared.refresh()
        if let pending = deepLinks.pendingFriendCode {
            deepLinks.pendingFriendCode = nil
            await add(pending)
        }
    }

    private func add(_ raw: String) async {
        guard let repository, let token = auth.accessToken else { return }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            switch try await repository.addFriend(code: value, token: token) {
            case .added(let name):
                Haptics.confirm()
                message = "\(name ?? "Neue:r Freund:in") ist jetzt in deiner Liste."
                codeInput = ""
                tab = .friends
                await load()
            case .unknownCode: message = "Diesen Code kennen wir nicht."
            case .ownCode: message = "Das ist dein eigener Code."
            }
        } catch {
            message = "Hinzufügen hat nicht geklappt. Bitte später erneut versuchen."
        }
    }

    private func respond(_ request: FriendRequest, accept: Bool) async {
        guard let repository, let token = auth.accessToken else { return }
        try? await repository.respondFriendRequest(from: request.person.id, accept: accept, token: token)
        if accept { Haptics.confirm() }
        await load()
    }
}


struct FriendsGoingGroup: Identifiable, Hashable {
    var id: UUID { event.id }
    let event: SocialEvent
    var people: [SocialPerson]
}

/// Freund im Freundeskreis-Band: großes Porträt, Vorname, optional Anzahl
/// kommender Konzerte als kleines Siegel.
private struct FriendCircleTile<Content: View>: View {
    let title: String
    var badge: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 7) {
            content
                .frame(width: 68, height: 68)
                .overlay(alignment: .bottomTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(KlangradarTheme.accent, in: .circle)
                            .overlay { Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2.5) }
                            .accessibilityLabel("\(badge) kommende Konzerte")
                    }
                }
            Text(title).font(.caption.weight(.medium)).lineLimit(1).frame(width: 76)
        }
    }
}

/// Gemeinsamer Abend als Plakat: Bild randlos, großer Datumsblock,
/// Titel, wer zugesagt hat, eigener Status.
private struct PlanPosterCard: View {
    let plan: ConcertPlan

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: plan.event.imageURL, maxPixel: 700) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { LinearGradient(colors: [KlangradarTheme.accent, KlangradarTheme.deepInk], startPoint: .topLeading, endPoint: .bottomTrailing) }
            }
            .frame(width: 270, height: 330)
            .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.25), .black.opacity(0.82)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text(plan.event.title)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .lineLimit(3)
                if let meeting = meetingLine {
                    Label(meeting, systemImage: "mappin.and.ellipse").font(.caption.weight(.medium)).lineLimit(1)
                } else if let venue = plan.event.venue {
                    Text(venue).font(.caption).opacity(0.85).lineLimit(1)
                }
                HStack(spacing: 8) {
                    AvatarStack(people: plan.going.map(\.person), size: 26)
                    Text(plan.going.isEmpty ? "Noch keine Zusagen" : "\(plan.going.count) dabei").font(.caption.weight(.medium))
                }
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .frame(width: 270, height: 330)
        .overlay(alignment: .topLeading) { dateBlock.padding(14) }
        .overlay(alignment: .topTrailing) { statusPill.padding(14) }
        .clipShape(.rect(cornerRadius: 26, style: .continuous))
        .contentShape(.rect(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder private var dateBlock: some View {
        if let start = plan.event.start {
            VStack(spacing: 0) {
                Text(KlangradarDateTime.string(start, format: "MMM").uppercased()).font(.caption2.weight(.bold)).foregroundStyle(KlangradarTheme.accent)
                Text(KlangradarDateTime.string(start, format: "d")).font(.system(size: 26, weight: .semibold, design: .serif))
                Text(KlangradarDateTime.string(start, format: "EE")).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 64)
            .background(.regularMaterial, in: .rect(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder private var statusPill: some View {
        let text: String? = switch plan.myStatus {
        case "invited": "Einladung"
        case "going": "Dabei"
        case "maybe": "Vielleicht"
        default: plan.isOwner ? "Dein Plan" : nil
        }
        if let text {
            Text(text)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(plan.myStatus == "invited" ? .white : .primary)
                .background(plan.myStatus == "invited" ? AnyShapeStyle(KlangradarTheme.accent) : AnyShapeStyle(.regularMaterial), in: .capsule)
        }
    }

    private var meetingLine: String? {
        let parts = [plan.meetingTime.map { "\(KlangradarDateTime.string($0, format: "HH:mm")) Uhr" }, plan.meetingPoint].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Konzertplakat im Raster, unten links die Freunde, die hingehen.
private struct FriendsGoingPoster: View {
    let group: FriendsGoingGroup

    var body: some View {
        Button {
            DeepLinkRouter.shared.handle(route: "/event/\(group.event.slug)")
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .aspectRatio(0.78, contentMode: .fit)
                    .overlay {
                        CachedAsyncImage(url: group.event.imageURL, maxPixel: 500) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { KlangradarTheme.accent.opacity(0.15).overlay { Image(systemName: "music.note").font(.title).foregroundStyle(KlangradarTheme.accent) } }
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        AvatarStack(people: group.people, size: 30, limit: 3).padding(10)
                    }
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.event.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(AvatarStack.names(group.people)) · \(group.event.start.map { KlangradarDateTime.string($0, format: "EE d. MMM") } ?? "")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .foregroundStyle(.primary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Eigener Freundescode als Eintrittskarte mit Abriss.
private struct FriendCodeTicket: View {
    let code: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DEIN FREUNDESCODE").font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(.white.opacity(0.7))
                Text(code ?? "······").font(.system(size: 30, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                Text("Wer ihn eingibt, ist sofort mit dir befreundet.").font(.caption).foregroundStyle(.white.opacity(0.75))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(.white.opacity(0.45))
                .frame(width: 1)
                .mask { VStack(spacing: 5) { ForEach(0..<14, id: \.self) { _ in Rectangle().frame(height: 4) } } }
                .padding(.vertical, 14)
            Group {
                if let code {
                    ShareLink(item: FriendInvite.message(code: code)) {
                        Image(systemName: "square.and.arrow.up").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Einladung teilen")
                }
            }
            .frame(width: 70)
        }
        .background(
            LinearGradient(colors: [KlangradarTheme.accent, KlangradarTheme.deepInk], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: TicketShape()
        )
    }
}

/// Rechteck mit zwei halbrunden Kerben auf Höhe des Abrisses.
private struct TicketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let notchX = rect.maxX - 70
        let radius: CGFloat = 10
        var notches = Path()
        notches.addEllipse(in: CGRect(x: notchX - radius, y: rect.minY - radius, width: radius * 2, height: radius * 2))
        notches.addEllipse(in: CGRect(x: notchX - radius, y: rect.maxY - radius, width: radius * 2, height: radius * 2))
        return Path(roundedRect: rect, cornerRadius: 20, style: .continuous).subtracting(notches)
    }
}

/// Leerer Zustand als ruhige Karte statt ContentUnavailableView-Liste.
private struct EmptyStageCard: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(KlangradarTheme.accent).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }
}
