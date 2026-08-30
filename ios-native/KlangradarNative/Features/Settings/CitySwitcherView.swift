import SwiftUI

/// "Stadt wechseln" — Nutzeranfrage: Städteauswahl analog zum Flutter-
/// Native iOS-Städteauswahl für die Profileinstellung. "Alle Städte" ist
/// bewusst ausschließlich eine Kartenoption; Home, Suche und Kalender haben
/// immer eine konkrete Heimatstadt.
struct CitySwitcherView: View {
    @ObservedObject var cityStore: CityStore
    var allowsAllCities = false
    @Environment(\.dismiss) private var dismiss

    @State private var isLocating = false
    @State private var locationError: String?

    var body: some View {
        NavigationStack {
            List {
                if allowsAllCities {
                    Section {
                        cityRow(name: "Alle Städte", subtitle: nil, isSelected: cityStore.selectedCity == nil) {
                            cityStore.select(nil)
                        }
                    }
                }

                Section("Städte") {
                    ForEach(cityStore.activeCities) { city in
                        cityRow(
                            name: cityDisplayName(for: city),
                            subtitle: countryLabel(for: city),
                            isSelected: cityStore.selectedCity?.id == city.id
                        ) { cityStore.select(city) }
                    }
                }

                Section {
                    Button {
                        Task { await recommendByLocation() }
                    } label: {
                        Label(
                            isLocating ? "Standort wird bestimmt …" : "Stadt anhand meines Standorts empfehlen",
                            systemImage: "location.fill"
                        )
                    }
                    .disabled(isLocating)
                    if let locationError { Text(locationError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Stadt wechseln")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { if cityStore.activeCities.isEmpty { await cityStore.load() } }
    }

    private func cityRow(name: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(isSelected ? KlangradarTheme.accent : Color.secondary.opacity(0.15))
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Deutschland-Städte bekommen keinen Zusatz (überwiegende Mehrheit),
    /// Wien als bisher einziges Nicht-DE-Land bekommt "Österreich" zur
    /// Unterscheidung -- einfacher als ein echtes country_code-Mapping hier
    /// zu duplizieren, für die aktuell fünf Städte ausreichend.
    private func countryLabel(for city: RegionOption) -> String? {
        city.name == "Wien" ? "Österreich" : "Deutschland"
    }

    private func cityDisplayName(for city: RegionOption) -> String {
        city.name == "München" ? city.name : "\(city.name) · Beta"
    }

    @MainActor
    private func recommendByLocation() async {
        isLocating = true
        locationError = nil
        defer { isLocating = false }
        do {
            let coordinate = try await LocationRequester().requestOnce()
            guard let nearest = cityStore.nearestCity(to: coordinate) else {
                locationError = "Für deinen Standort konnte keine passende Stadt gefunden werden."
                return
            }
            cityStore.select(nearest)
        } catch {
            locationError = error.localizedDescription
        }
    }
}

/// Kompaktes, systemeigenes Menü für die Tab-Leisten. Anders als der
/// Profil-Dialog verdeckt es nicht den Inhalt und entspricht dem bisherigen
/// kleinen Karten-Dropdown.
struct CityCompactMenu: View {
    @ObservedObject var cityStore: CityStore
    var allowsAllCities = false

    var body: some View {
        Menu {
            if allowsAllCities {
                Button {
                    cityStore.select(nil)
                } label: {
                    menuLabel("Alle Städte", selected: cityStore.selectedCity == nil)
                }
            }
            ForEach(cityStore.activeCities) { city in
                Button {
                    cityStore.select(city)
                } label: {
                    menuLabel(city.name, selected: cityStore.selectedCity?.id == city.id)
                }
            }
        } label: {
            Label(cityStore.selectedCity?.name ?? (allowsAllCities ? "Alle Städte" : "Stadt"), systemImage: "building.2")
                .font(.subheadline.weight(.medium))
        }
        .accessibilityLabel("Stadt auswählen")
    }

    @ViewBuilder
    private func menuLabel(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}
