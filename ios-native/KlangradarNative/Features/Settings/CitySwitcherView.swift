import SwiftUI

/// "Stadt wechseln" — Nutzeranfrage: Städteauswahl analog zum Flutter-
/// Die gestaltete SwiftUI-Auswahl für Home, Suche, Kalender und Profil.
/// Sie ist bewusst kein technisches List-Menü: die Stadt ist eine zentrale
/// Einstellung und soll sich wie ein eigener Klangradar-Bereich anfühlen.
struct CitySwitcherView: View {
    @ObservedObject var cityStore: CityStore
    var allowsAllCities = false
    @Environment(\.dismiss) private var dismiss

    @State private var isLocating = false
    @State private var locationError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    cityHeader

                    ForEach(cityStore.activeCities) { city in
                        cityRow(
                            name: city.name,
                            subtitle: countryLabel(for: city),
                            isSelected: cityStore.selectedCity?.id == city.id
                        ) { cityStore.select(city) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .background(KlangradarBackground().ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task { if cityStore.activeCities.isEmpty { await cityStore.load() } }
    }

    private var cityHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(KlangradarTheme.accent)

            Text("Stadt wechseln")
                .font(.largeTitle.bold())
            Text("Du kannst deine Stadt jederzeit schnell ändern. Personen, Ensembles und Werke bleiben stadtübergreifend verfügbar.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                Task { await recommendByLocation() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.north.fill")
                        .rotationEffect(.degrees(28))
                    Text(isLocating ? "Standort wird bestimmt …" : "Stadt anhand meines Standorts empfehlen")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .foregroundStyle(KlangradarTheme.accent)
            .background(KlangradarTheme.accent.opacity(0.14), in: .capsule)
            .disabled(isLocating)

            if let locationError {
                Text(locationError).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(.top, 14)
    }

    private func cityRow(name: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(KlangradarTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline).foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.44), in: .rect(cornerRadius: 18))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Deutschland-Städte bekommen keinen Zusatz (überwiegende Mehrheit),
    /// Wien als bisher einziges Nicht-DE-Land bekommt "Österreich" zur
    /// Unterscheidung -- einfacher als ein echtes country_code-Mapping hier
    /// zu duplizieren, für die aktuell fünf Städte ausreichend.
    private func countryLabel(for city: RegionOption) -> String? {
        city.name == "Wien" ? "Österreich" : "Deutschland"
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

/// Der kleine Stadt-Chip folgt der früheren Kopfzeile der App. Auf Home,
/// Suche und Kalender öffnet er die gestaltete Auswahl; ausschließlich die
/// Karte verwendet das platzsparende Dropdown mit "Alle Städte".
struct CityCompactMenu: View {
    @ObservedObject var cityStore: CityStore
    var allowsAllCities = false
    var isMapMenu = false
    @State private var showsCitySwitcher = false

    var body: some View {
        Group {
            if isMapMenu {
                mapMenu
            } else {
                // Kein .buttonStyle(.plain): das würde die automatische
                // native Liquid-Glass-Kapsel unterdrücken, die iOS 26 für
                // ToolbarItem-Inhalte selbst zeichnet.
                Button { showsCitySwitcher = true } label: { chipLabel }
            }
        }
        .sheet(isPresented: $showsCitySwitcher) {
            CitySwitcherView(cityStore: cityStore)
        }
        .accessibilityLabel("Stadt auswählen")
    }

    private var mapMenu: some View {
        Menu {
            if allowsAllCities {
                Button {
                    cityStore.select(nil)
                } label: {
                    menuLabel(
                        "Alle Städte",
                        selected: cityStore.selectedCity == nil,
                        showsSelectionIndicator: true
                    )
                }
            }
            ForEach(cityStore.activeCities) { city in
                Button {
                    cityStore.select(city)
                } label: {
                    menuLabel(
                        city.name,
                        selected: cityStore.selectedCity?.id == city.id,
                        showsSelectionIndicator: true
                    )
                }
            }
        } label: { chipLabel }
    }

    // Kein eigener Hintergrund/Glass-Effekt hier: ToolbarItem(.topBarTrailing)
    // umschließt seinen Inhalt auf iOS 26 bereits automatisch mit nativem
    // Liquid Glass -- ein zusätzlicher .glassEffect()/eigener Kapsel-
    // Hintergrund erzeugte sichtbar "ein Glas im Glas".
    private var chipLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.north.fill")
                .rotationEffect(.degrees(28))
                .font(.caption)
            Text(cityStore.selectedCity?.name ?? (allowsAllCities ? "Alle Städte" : "Stadt"))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(KlangradarTheme.accent)
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    // Native UIMenu ignoriert `.opacity(0)` auf verschachtelten Images beim
    // Konvertieren von SwiftUI-Buttons zu UIMenuElements -- ein "unsichtbarer"
    // Haken wurde dadurch für ALLE Zeilen sichtbar gerendert. Das Icon daher
    // nur einbauen, wenn die Zeile wirklich ausgewählt ist.
    @ViewBuilder
    private func menuLabel(
        _ title: String,
        selected: Bool,
        showsSelectionIndicator: Bool
    ) -> some View {
        if showsSelectionIndicator && selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}
