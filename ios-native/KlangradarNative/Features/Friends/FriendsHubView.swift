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

    var body: some View {
        Group {
            if auth.userID == nil {
                ContentUnavailableView {
                    Label("Gemeinsam ins Konzert", systemImage: "person.2.wave.2")
                } description: {
                    Text("Melde dich an, um Freunde hinzuzufügen, Konzertabende zu planen und zu sehen, wohin deine Freunde gehen.")
                }
            } else {
                List {
                    Section { header }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                    Section {
                        Picker("Bereich", selection: $tab) {
                            ForEach(FriendsHubTab.allCases) { tab in Text(label(for: tab)).tag(tab) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)

                    switch tab {
                    case .activity: activitySection
                    case .plans: plansSection
                    case .friends: friendsSections
                    }
                }
                .listStyle(.insetGrouped)
                .animation(.snappy, value: tab)
            }
        }
        .navigationTitle("Freunde")
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
        .navigationDestination(for: PlanRoute.self) { route in
            PlanDetailView(planID: route.id) { await load() }
        }
        .navigationDestination(for: ProfileRoute.self) { route in
            UserProfileView(userID: route.id)
        }
        .task {
            tab = initialTab
            await load()
        }
        .refreshable { await load() }
        .onChange(of: deepLinks.pendingFriendCode) { _, value in
            guard let value else { return }
            deepLinks.pendingFriendCode = nil
            Task { await add(value) }
        }
    }

    private func label(for tab: FriendsHubTab) -> String {
        switch tab {
        case .plans where social.pendingPlanInvites > 0: "Pläne (\(social.pendingPlanInvites))"
        case .friends where social.incomingRequests > 0: "Freunde (\(social.incomingRequests))"
        default: tab.rawValue
        }
    }

    // MARK: Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                AvatarStack(people: friends.map { SocialPerson(id: $0.id, name: $0.name, avatarURL: $0.avatarURL) }, size: 34, limit: 5)
                    .opacity(friends.isEmpty ? 0 : 1)
                    .frame(minHeight: friends.isEmpty ? 0 : 34)
                Spacer(minLength: 0)
            }
            Text(friends.isEmpty ? "Konzerte sind schöner zu zweit" : "\(friends.count) \(friends.count == 1 ? "Freund:in" : "Freunde") auf Klangradar")
                .font(.title2.bold())
            Text("Plant Konzertabende gemeinsam, seht, wohin eure Freunde gehen, und teilt eure Lieblingslisten.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { showsFindFriends = true } label: {
                    Label("Freunde finden", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(KlangradarTheme.accent)
                if let code {
                    ShareLink(item: FriendInvite.message(code: code)) {
                        Label("Einladen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
        }
        .padding(18)
        .background(.thinMaterial, in: .rect(cornerRadius: 24, style: .continuous))
        .padding(.vertical, 6)
    }

    // MARK: Aktivität

    @ViewBuilder private var activitySection: some View {
        if activity.isEmpty && !isLoading {
            Section {
                ContentUnavailableView("Noch ruhig hier", systemImage: "music.note.list",
                                       description: Text(friends.isEmpty ? "Sobald du Freunde hast, siehst du hier, zu welchen Konzerten sie gehen und wie es ihnen gefallen hat." : "Deine Freunde haben in den letzten 30 Tagen nichts geteilt."))
            }
        } else {
            Section {
                ForEach(activity) { item in ActivityRow(item: item) }
            }
        }
    }

    // MARK: Pläne

    @ViewBuilder private var plansSection: some View {
        if plans.isEmpty && !isLoading {
            Section {
                ContentUnavailableView {
                    Label("Noch keine Pläne", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Öffne ein Konzert und tippe auf „Mit Freunden planen“. Deine Freunde können zu- oder absagen, ihr vereinbart Treffpunkt und Uhrzeit.")
                }
            }
        } else {
            let invites = plans.filter { $0.myStatus == "invited" }
            if !invites.isEmpty {
                Section("Einladungen") { ForEach(invites) { plan in PlanCard(plan: plan) } }
            }
            let others = plans.filter { $0.myStatus != "invited" }
            if !others.isEmpty {
                Section("Kommende Konzertabende") { ForEach(others) { plan in PlanCard(plan: plan) } }
            }
        }
    }

    // MARK: Freunde

    @ViewBuilder private var friendsSections: some View {
        let incoming = requests.filter(\.incoming)
        if !incoming.isEmpty {
            Section("Anfragen") {
                ForEach(incoming) { request in
                    HStack(spacing: 12) {
                        NavigationLink(value: ProfileRoute(id: request.person.id)) {
                            HStack(spacing: 12) {
                                SocialAvatar(name: request.person.name, url: request.person.avatarURL, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(request.person.name).font(.headline)
                                    if request.mutualFriends > 0 {
                                        Text("\(request.mutualFriends) gemeinsame \(request.mutualFriends == 1 ? "Freund:in" : "Freunde")").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        HStack(spacing: 8) {
                            Button { Task { await respond(request, accept: false) } } label: { Image(systemName: "xmark") }
                                .buttonStyle(.bordered).tint(.secondary)
                                .accessibilityLabel("Ablehnen")
                            Button { Task { await respond(request, accept: true) } } label: { Image(systemName: "checkmark") }
                                .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent)
                                .accessibilityLabel("Annehmen")
                        }
                        .controlSize(.small)
                    }
                }
            }
        }

        Section {
            HStack {
                TextField("Freundescode eingeben", text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Hinzufügen") { Task { await add(codeInput) } }
                    .disabled(codeInput.trimmingCharacters(in: .whitespaces).count < 6)
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Per Code")
        } footer: {
            if let code { Text("Dein Code: \(code). Wer ihn eingibt, ist sofort mit dir befreundet.") }
        }

        Section("Freunde") {
            if friends.isEmpty && !isLoading {
                Text("Noch keine Freunde. Lade jemanden ein oder finde Freunde über deine Kontakte.").foregroundStyle(.secondary)
            }
            ForEach(friends) { friend in
                NavigationLink(value: ProfileRoute(id: friend.id)) {
                    HStack(spacing: 12) {
                        SocialAvatar(name: friend.name, url: friend.avatarURL, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.name).font(.headline)
                            Text(friend.upcomingCount == 0 ? "Keine geplanten Konzerte" : friend.upcomingCount == 1 ? "1 kommendes Konzert" : "\(friend.upcomingCount) kommende Konzerte")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        let outgoing = requests.filter { !$0.incoming }
        if !outgoing.isEmpty {
            Section("Gesendete Anfragen") {
                ForEach(outgoing) { request in
                    HStack(spacing: 12) {
                        SocialAvatar(name: request.person.name, url: request.person.avatarURL, size: 36)
                        Text(request.person.name)
                        Spacer()
                        RelationButton(person: SocialPerson(id: request.person.id, name: request.person.name, avatarURL: request.person.avatarURL, status: .requested), source: "profile") { _ in
                            Task { await load() }
                        }
                    }
                }
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

struct PlanRoute: Hashable { let id: UUID }
struct ProfileRoute: Hashable { let id: UUID }

/// Eintrag im Freunde-Feed.
private struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                NavigationLink(value: ProfileRoute(id: item.person.id)) {
                    SocialAvatar(name: item.person.name, url: item.person.avatarURL, size: 36)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    (Text(item.person.name).fontWeight(.semibold) + Text(" " + verb))
                        .font(.subheadline)
                    if let date = item.happenedAt {
                        Text(date.socialRelative).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if item.kind == .rated, let stars = item.stars {
                VStack(alignment: .leading, spacing: 4) {
                    StarRating(stars: .constant(stars), size: 14, editable: false)
                    if let comment = item.comment { Text("„\(comment)“").font(.subheadline).italic() }
                }
                .padding(.leading, 46)
            }
            SocialEventRow(event: item.event).padding(.leading, 46)
        }
        .padding(.vertical, 4)
    }

    private var verb: String {
        switch item.kind {
        case .attending: "geht hin"
        case .attended: "war dort"
        case .rated: "hat bewertet"
        }
    }
}
