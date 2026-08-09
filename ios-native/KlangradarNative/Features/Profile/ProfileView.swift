import SwiftUI

struct ProfileView: View {
    let usesPreviewData: Bool
    @ObservedObject var auth: AuthStore
    let userRepository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository

    @AppStorage("appearance") private var appearance = "system"
    @State private var showsLogin = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(KlangradarTheme.accent)
                        VStack(alignment: .leading) {
                            Text("Klangradar")
                                .font(.headline)
                            Text(usesPreviewData ? "Preview-Modus" : "Mit Supabase verbunden")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Account") {
                    accountContent
                }

                Section("Dein Klangradar") {
                    NavigationLink {
                        FavoriteEventsView(auth: auth, repository: userRepository, eventRepository: eventRepository, contentRepository: contentRepository)
                    } label: {
                        Label("Favoriten", systemImage: "heart")
                    }
                    NavigationLink {
                        InterestsView(auth: auth, repository: userRepository)
                    } label: {
                        Label("Interessen", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        NotificationSettingsView(auth: auth, repository: userRepository)
                    } label: {
                        Label("Benachrichtigungen", systemImage: "bell")
                    }
                }

                Section("Darstellung") {
                    Picker("Erscheinungsbild", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Hell").tag("light")
                        Text("Dunkel").tag("dark")
                    }
                }

                Section("Über Klangradar") {
                    Link("Datenschutz", destination: URL(string: "https://klangradar.app/datenschutz")!)
                    Link("Impressum", destination: URL(string: "https://klangradar.app/impressum")!)
                }
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $showsLogin) {
                EmailCodeLoginView(auth: auth)
            }
        }
    }

    @ViewBuilder
    private var accountContent: some View {
        switch auth.state {
        case .unavailable:
            Label("Im Preview-Modus nicht verfügbar", systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView("Sitzung wird vorbereitet …")
        case .anonymous:
            Button("Mit E-Mail anmelden", systemImage: "envelope") {
                showsLogin = true
            }
        case let .authenticated(session):
            LabeledContent("Angemeldet als", value: session.user.email ?? "Klangradar Account")
            Button("Abmelden", role: .destructive) {
                Task { try? await auth.signOut() }
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Button("Erneut versuchen") {
                Task { await auth.bootstrap() }
            }
        }
    }
}

private struct EmailCodeLoginView: View {
    @ObservedObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var didSendCode = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-Mail-Adresse", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    if didSendCode {
                        TextField("Bestätigungscode", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                    }
                } footer: {
                    Text("Klangradar sendet einen einmaligen Anmeldecode. Ein Passwort ist nicht notwendig.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(didSendCode ? "Code bestätigen" : "Code senden") {
                        Task { await submit() }
                    }
                    .disabled(
                        isWorking
                            || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (didSendCode && code.isEmpty)
                    )
                }
            }
            .navigationTitle("Anmelden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            if didSendCode {
                try await auth.verifyEmailCode(code, email: email)
                dismiss()
            } else {
                try await auth.sendEmailCode(to: email)
                didSendCode = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FavoriteEventsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var events: [ConcertEvent] = []

    var body: some View {
        List(events) { event in NavigationLink(value: event) { Label(event.title, systemImage: "heart.fill") } }
            .overlay { if events.isEmpty { ContentUnavailableView("Noch keine Favoriten", systemImage: "heart", description: Text("Markierte Veranstaltungen erscheinen hier.")) } }
            .navigationTitle("Favoriten")
            .navigationDestination(for: ConcertEvent.self) { EventDetailView(event: $0, repository: eventRepository, contentRepository: contentRepository) }
            .task {
                guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
                events = (try? await repository.favoriteEvents(userID: id, token: token)) ?? []
            }
    }
}

private struct InterestsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @State private var category: InterestCategory = .genre
    @State private var options: [InterestOption] = []
    @State private var selected: Set<String> = []
    @State private var searchText = ""

    private var filteredOptions: [InterestOption] {
        searchText.isEmpty ? options : options.filter { $0.label.localizedStandardContains(searchText) }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(InterestCategory.allCases, id: \.self) { item in
                            Button { category = item } label: {
                                Label(item.title, systemImage: item.systemImage)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(category == item ? KlangradarTheme.accent : Color.secondary.opacity(0.12), in: .capsule)
                                    .foregroundStyle(category == item ? .white : .primary)
                            }.buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            Section("\(category.title) · \(selected.count) ausgewählt") {
                ForEach(filteredOptions) { option in
                    Button { toggle(option.id) } label: {
                        HStack { Text(option.label).foregroundStyle(.primary); Spacer(); Image(systemName: selected.contains(option.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(option.id) ? KlangradarTheme.accent : .secondary) }
                    }
                }
            }
        }
        .navigationTitle("Interessen")
        .searchable(text: $searchText, prompt: "\(category.title) durchsuchen")
        .task(id: category) { searchText = ""; await load() }
    }

    private func load() async {
        guard let repository else { return }
        options = (try? await repository.interestOptions(category)) ?? []
        guard let id = auth.userID, let token = auth.accessToken else { return }
        selected = (try? await repository.selectedInterests(category, userID: id, token: token)) ?? []
    }

    private func toggle(_ id: String) {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        let newValue = !selected.contains(id)
        if newValue { selected.insert(id) } else { selected.remove(id) }
        Task { try? await repository.setInterest(category, id: id, selected: newValue, userID: userID, token: token) }
    }
}

private struct NotificationSettingsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @State private var preferences = NotificationPreferences()

    var body: some View {
        Form {
            Toggle("Neue passende Veranstaltungen", isOn: binding(\.newMatchingEvents, "new_matching_events"))
            Toggle("Preisänderungen", isOn: binding(\.priceChanges, "price_changes"))
            Toggle("Fast ausverkauft", isOn: binding(\.almostSoldOut, "almost_sold_out"))
            Toggle("Erinnerung am Vortag", isOn: binding(\.reminderDayBefore, "reminder_day_before"))
            Toggle("Neue Termine gefolgter Ensembles", isOn: binding(\.followedEnsembleNewEvent, "followed_ensemble_new_event"))
        }
        .navigationTitle("Benachrichtigungen")
        .task {
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            preferences = (try? await repository.preferences(userID: id, token: token)) ?? NotificationPreferences()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>, _ column: String) -> Binding<Bool> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in
            preferences[keyPath: keyPath] = value
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            Task { try? await repository.setPreference(userID: id, token: token, column: column, value: value) }
        })
    }
}
