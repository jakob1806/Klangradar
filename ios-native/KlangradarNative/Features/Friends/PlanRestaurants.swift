// Erstellt von Claude Code (18.11.2026): Gemeinsamer Abend – Restaurants im
// Konzertplan vorschlagen und abstimmen (eine Stimme pro Person).
import MapKit
import SwiftUI

struct PlanRestaurant: Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let address: String?
    let votes: Int
    let mine: Bool
}

extension UserRepository {
    func planRestaurants(_ planID: UUID, token: String) async throws -> [PlanRestaurant] {
        let value: JSONValue = try await client.rpc("plan_restaurants", parameters: ["p_plan_id": .string(planID.uuidString)], accessToken: token)
        guard case let .array(items) = value else { return [] }
        return items.compactMap { item in
            guard case let .object(row) = item, let id = row.uuid("id"), let name = row.string("name") else { return nil }
            return PlanRestaurant(id: id, name: name, address: row.string("address"), votes: row.integer("votes") ?? 0, mine: row.bool("mine") ?? false)
        }
    }

    func addPlanRestaurant(_ planID: UUID, name: String, address: String?, latitude: Double, longitude: Double, token: String) async throws {
        var parameters: JSONObject = ["p_plan_id": .string(planID.uuidString), "p_name": .string(name)]
        if let address { parameters["p_address"] = .string(address) }
        parameters["p_lat"] = .number(latitude)
        parameters["p_lng"] = .number(longitude)
        let _: JSONValue = try await client.rpc("add_plan_restaurant", parameters: parameters, accessToken: token)
    }

    func votePlanRestaurant(_ planID: UUID, restaurantID: UUID, token: String) async throws {
        let _: JSONValue = try await client.rpc("vote_plan_restaurant", parameters: ["p_plan_id": .string(planID.uuidString), "p_restaurant_id": .string(restaurantID.uuidString)], accessToken: token)
    }
}

/// Abschnitt im Konzertplan: „Wo essen wir vorher?“
struct PlanRestaurantSection: View {
    let planID: UUID
    let venueName: String?
    @State private var options: [PlanRestaurant] = []
    @State private var showsSearch = false

    var body: some View {
        Section {
            ForEach(options) { option in
                Button { Task { await vote(option) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.mine ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(option.mine ? KlangradarTheme.accent : Color.secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                            if let address = option.address { Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        Text(option.votes == 1 ? "1 Stimme" : "\(option.votes) Stimmen").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            Button("Restaurant vorschlagen", systemImage: "fork.knife") { showsSearch = true }
        } header: {
            Text("Wo essen wir vorher?")
        } footer: {
            if !options.isEmpty { Text("Tippe ein Restaurant an, um dafür zu stimmen. Jede:r hat eine Stimme.") }
        }
        .task { await load() }
        .sheet(isPresented: $showsSearch) {
            NavigationStack {
                RestaurantSearchView(venueName: venueName) { item in
                    showsSearch = false
                    Task { await add(item) }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        options = (try? await repository.planRestaurants(planID, token: token)) ?? []
    }

    private func vote(_ option: PlanRestaurant) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.votePlanRestaurant(planID, restaurantID: option.id, token: token)
        Haptics.light()
        await load()
    }

    private func add(_ item: MKMapItem) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        // Nur einfache Werte weitergeben (MKMapItem ist nicht Sendable).
        let name = item.name ?? "Restaurant", address = item.placemark.title
        let coordinate = item.placemark.coordinate
        try? await repository.addPlanRestaurant(planID, name: name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude, token: token)
        Haptics.confirm()
        await load()
    }
}

/// Restaurants in der Nähe der Spielstätte suchen (Apple Karten).
private struct RestaurantSearchView: View {
    let venueName: String?
    let onPick: (MKMapItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var region: MKCoordinateRegion?

    var body: some View {
        List(results, id: \.self) { item in
            Button { onPick(item) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "Restaurant").foregroundStyle(.primary)
                    if let title = item.placemark.title { Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
        }
        .overlay { if results.isEmpty { ContentUnavailableView("Restaurants in der Nähe", systemImage: "fork.knife", description: Text(venueName.map { "Rund um \($0)" } ?? "")) } }
        .searchable(text: $query, prompt: "Restaurant suchen")
        .navigationTitle("Restaurant vorschlagen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        .task { await locateVenue(); await search() }
        .onChange(of: query) { _, _ in Task { await search() } }
    }

    private func locateVenue() async {
        guard region == nil, let venueName else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = venueName
        if let item = try? await MKLocalSearch(request: request).start().mapItems.first {
            region = MKCoordinateRegion(center: item.placemark.coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)
        }
    }

    private func search() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.isEmpty ? "Restaurant" : query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .brewery, .winery])
        if let region { request.region = region }
        results = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
    }
}
