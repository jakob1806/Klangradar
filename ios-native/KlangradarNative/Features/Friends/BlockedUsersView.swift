// Erstellt von Claude Code (12.11.2026): Blockierte Personen ansehen und
// die Blockierung wieder aufheben (Profil → Einstellungen).
import SwiftUI

struct BlockedUsersView: View {
    @State private var people: [SocialPerson] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pending: SocialPerson?

    var body: some View {
        List {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            ForEach(people) { person in
                HStack(spacing: 12) {
                    CachedAsyncImage(url: person.avatarURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary) }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(.circle)
                    Text(person.name)
                    Spacer()
                    Button("Aufheben") { pending = person }
                        .buttonStyle(.bordered)
                }
            }
        }
        .overlay {
            if isLoading && people.isEmpty {
                ProgressView()
            } else if people.isEmpty && errorMessage == nil {
                ContentUnavailableView("Niemand blockiert", systemImage: "hand.raised", description: Text("Wenn du jemanden blockierst, erscheint die Person hier."))
            }
        }
        .navigationTitle("Blockierte Personen")
        .confirmationDialog("Blockierung von \(pending?.name ?? "") aufheben?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Aufheben") { if let person = pending { Task { await unblock(person) } } }
        } message: {
            Text("Ihr könnt euch danach wieder finden. Eine Freundschaft musst du neu anfragen.")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else {
            isLoading = false; errorMessage = "Bitte melde dich an."; return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            people = try await repository.blockedUsers(token: token)
            errorMessage = nil
        } catch {
            errorMessage = "Die Liste konnte gerade nicht geladen werden."
        }
    }

    private func unblock(_ person: SocialPerson) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        do {
            try await repository.unblockUser(person.id, token: token)
            people.removeAll { $0.id == person.id }
            Haptics.confirm()
            await SocialStore.shared.refresh()
        } catch {
            errorMessage = "Aufheben hat nicht geklappt. Bitte versuch es erneut."
        }
    }
}
