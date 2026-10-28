import Contacts
import SwiftUI

/// Freunde finden: Suche, Kontakte (nur gehasht), Vorschläge, Einladungslink.
struct FindFriendsView: View {
    let code: String?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SocialPerson] = []
    @State private var suggestions: [SocialPerson] = []
    @State private var contactMatches: [SocialPerson]?
    @State private var contactState: ContactState = .idle
    @State private var searchTask: Task<Void, Never>?

    private enum ContactState { case idle, loading, denied, done }

    var body: some View {
        List {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Section("Suchergebnisse") {
                    if results.isEmpty {
                        Text("Keine öffentlichen Profile gefunden.").foregroundStyle(.secondary)
                    }
                    ForEach(results) { person in personRow(person, source: "search") }
                }
            } else {
                inviteSection
                contactsSection
                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { person in personRow(person, source: "suggestion") }
                    } header: {
                        Text("Vorschläge für dich")
                    } footer: {
                        Text("Freunde deiner Freunde und Menschen mit ähnlichem Musikgeschmack.")
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name suchen")
        .onChange(of: query) { _, value in scheduleSearch(value) }
        .navigationTitle("Freunde finden")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        .task { await loadSuggestions() }
    }

    // MARK: Abschnitte

    @ViewBuilder private var inviteSection: some View {
        if let code {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "link.circle.fill").font(.system(size: 38)).foregroundStyle(KlangradarTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Freunde einladen").font(.headline)
                            Text("Wer deinen Link öffnet, ist sofort mit dir verbunden.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text(FriendInvite.link(code: code).absoluteString.replacingOccurrences(of: "https://", with: ""))
                            .font(.footnote.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button {
                            UIPasteboard.general.url = FriendInvite.link(code: code)
                            Haptics.confirm()
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Link kopieren")
                    }
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 10))
                    ShareLink(item: FriendInvite.message(code: code)) {
                        Label("Link teilen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KlangradarTheme.accent)
                    .controlSize(.large)
                }
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder private var contactsSection: some View {
        Section {
            switch contactState {
            case .idle:
                Button {
                    Task { await scanContacts() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.checkmark").font(.title2).foregroundStyle(KlangradarTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kontakte durchsuchen").foregroundStyle(.primary)
                            Text("Findet Kontakte, die Klangradar nutzen und auffindbar sind.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            case .loading:
                HStack { ProgressView(); Text("Kontakte werden abgeglichen …").foregroundStyle(.secondary) }
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kein Zugriff auf Kontakte").font(.subheadline.weight(.semibold))
                    Text("Erlaube den Zugriff in den Einstellungen, um Freunde aus deinen Kontakten zu finden.").font(.caption).foregroundStyle(.secondary)
                    Button("Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.subheadline)
                }
            case .done:
                if let contactMatches, !contactMatches.isEmpty {
                    ForEach(contactMatches) { person in personRow(person, source: "contacts") }
                } else {
                    Text("Noch keiner deiner Kontakte ist auffindbar. Lade sie mit deinem Link ein.").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Aus deinen Kontakten")
        } footer: {
            Text("E-Mail-Adressen und Telefonnummern werden auf deinem iPhone verschlüsselt (SHA-256) und nur so abgeglichen. Klangradar speichert deine Kontakte nicht.")
        }
    }

    private func personRow(_ person: SocialPerson, source: String) -> some View {
        HStack(spacing: 12) {
            NavigationLink { UserProfileView(userID: person.id) } label: {
                HStack(spacing: 12) {
                    SocialAvatar(name: person.name, url: person.avatarURL, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).font(.headline).foregroundStyle(.primary)
                        if let detail = person.detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            RelationButton(person: person, source: source)
        }
    }

    // MARK: Laden

    private func loadSuggestions() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        suggestions = (try? await repository.suggestedFriends(token: token)) ?? []
    }

    private func scheduleSearch(_ value: String) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
            let found = (try? await repository.searchProfiles(trimmed, token: token)) ?? []
            if !Task.isCancelled { results = found }
        }
    }

    private func scanContacts() async {
        let store = CNContactStore()
        contactState = .loading
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        guard granted else { contactState = .denied; return }
        let hashes = await Task.detached(priority: .userInitiated) { () -> [String] in
            var values = Set<String>()
            let request = CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor, CNContactPhoneNumbersKey as CNKeyDescriptor])
            try? CNContactStore().enumerateContacts(with: request) { contact, _ in
                for email in contact.emailAddresses { values.insert(ContactHashing.hash(ContactHashing.normalizedEmail(email.value as String))) }
                for phone in contact.phoneNumbers {
                    if let normalized = ContactHashing.normalizedPhone(phone.value.stringValue) { values.insert(ContactHashing.hash(normalized)) }
                }
            }
            return Array(values)
        }.value
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { contactState = .done; return }
        var matches: [SocialPerson] = []
        // In Paketen, damit auch große Adressbücher zuverlässig durchgehen.
        for chunk in stride(from: 0, to: hashes.count, by: 1500).map({ Array(hashes[$0..<min($0 + 1500, hashes.count)]) }) {
            matches += (try? await repository.matchContacts(hashes: chunk, token: token)) ?? []
        }
        contactMatches = Dictionary(matches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values.sorted { $0.name < $1.name }
        contactState = .done
    }
}

/// Privatsphäre & Social-Profil.
struct SocialSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = SocialSettings()
    @State private var original = SocialSettings()
    @State private var phone = ""
    @State private var isLoaded = false
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                TextField("Kurz über dich, z. B. „Mahler-Fan, Abo im Herkulessaal“", text: $settings.bio, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: settings.bio) { _, value in if value.count > 160 { settings.bio = String(value.prefix(160)) } }
            } header: {
                Text("Über mich")
            } footer: {
                Text("\(settings.bio.count)/160")
            }

            Section {
                Toggle("Aktivität mit Freunden teilen", isOn: $settings.shareActivity)
            } footer: {
                Text("Freunde sehen im Feed, zu welchen Konzerten du gehst, wo du warst und wie es dir gefallen hat. Deine Merkliste bleibt privat.")
            }

            Section {
                Toggle("Öffentliches Profil", isOn: $settings.isPublic)
            } footer: {
                Text("Andere können dich über die Suche finden und deine Lieblingskomponist:innen und Konzertanzahl sehen. Geplante Konzerte sehen weiterhin nur Freunde.")
            }

            Section {
                Toggle("Über Kontakte auffindbar", isOn: $settings.contactDiscoverable)
                if settings.contactDiscoverable {
                    TextField("Telefonnummer (optional)", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                }
            } footer: {
                Text("Wer deine E-Mail-Adresse oder Telefonnummer gespeichert hat, kann dich finden. Die Nummer wird nur verschlüsselt (SHA-256) gespeichert.")
            }
        }
        .navigationTitle("Privatsphäre")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { Task { await save() } }.fontWeight(.semibold).disabled(!isLoaded || isSaving)
            }
        }
        .task {
            guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
            if let loaded = try? await repository.socialSettings(token: token) {
                settings = loaded
                original = loaded
            }
            isLoaded = true
        }
    }

    private func save() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isSaving = true
        defer { isSaving = false }
        try? await repository.updateSocialSettings(settings, token: token)
        let phoneHash = ContactHashing.normalizedPhone(phone).map(ContactHashing.hash)
        if settings.contactDiscoverable != original.contactDiscoverable || phoneHash != nil {
            try? await repository.setContactDiscovery(settings.contactDiscoverable, phoneHash: phoneHash, token: token)
        }
        Haptics.confirm()
        dismiss()
    }
}
