import SwiftUI

/// "Stadt wechseln" — Nutzeranfrage: Städteauswahl analog zum Flutter-
/// Die gestaltete SwiftUI-Auswahl für Home, Suche, Kalender und Profil.
/// Sie ist bewusst kein technisches List-Menü: die Stadt ist eine zentrale
/// Einstellung und soll sich wie ein eigener Klangradar-Bereich anfühlen.
struct CitySwitcherView: View {
    @ObservedObject var cityStore: CityStore
    var allowsAllCities = false
    var embedsNavigationStack = true
    @Environment(\.dismiss) private var dismiss

    @State private var isLocating = false
    @State private var locationError: String?

    @ViewBuilder
    var body: some View {
        if embedsNavigationStack {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                cityHeader

                LazyVStack(spacing: 12) {
                    ForEach(displayCities) { city in
                        cityRow(
                            name: city.name,
                            subtitle: countryLabel(for: city),
                            isSelected: cityStore.selectedCity?.id == city.id
                        ) { cityStore.select(city) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .background(KlangradarBackground().ignoresSafeArea())
        .toolbar {
            if embedsNavigationStack {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle(embedsNavigationStack ? "" : "Stadt wechseln")
        .navigationBarTitleDisplayMode(.inline)
        .task { if cityStore.activeCities.isEmpty { await cityStore.load() } }
    }

    private var cityHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(KlangradarTheme.accent)

            Text("Stadt wechseln")
                .font(.largeTitle.bold())
            Text("Du kannst deine Stadt jederzeit schnell ändern. Personen, Ensembles und Werke bleiben stadtübergreifend verfügbar.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                Task { await recommendByLocation() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.north.fill")
                        .rotationEffect(.degrees(38))
                    Text(isLocating ? "Standort wird bestimmt …" : "Stadt anhand meines Standorts empfehlen")
                }
                .font(.body)
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
        .padding(.top, 38)
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
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.white.opacity(0.44), in: .rect(cornerRadius: 24))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var displayCities: [RegionOption] {
        let order = ["München", "Berlin", "Hamburg", "Wien", "Frankfurt am Main"]
        return cityStore.activeCities.sorted { left, right in
            let leftIndex = order.firstIndex(of: left.name) ?? order.count
            let rightIndex = order.firstIndex(of: right.name) ?? order.count
            if leftIndex == rightIndex { return left.name.localizedStandardCompare(right.name) == .orderedAscending }
            return leftIndex < rightIndex
        }
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
                Button { showsCitySwitcher = true } label: { chipLabel }
                    .buttonStyle(.plain)
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
        } label: { chipLabel }
    }

    // Nutzerfeedback: Städte-Chip soll denselben Glas-Stil wie "Filter" und
    // der Standort-Button auf VenueMapView zeigen — vorher auf iOS 26 gar
    // kein eigener Hintergrund (verließ sich auf das automatische, davon
    // optisch abweichende Menu-Chrome), darunter .regularMaterial statt der
    // gemeinsamen LiquidGlassSurface-Komponente. Jetzt in allen drei Fällen
    // exakt dieselbe Komponente wie auf der Karte.
    private var chipLabel: some View {
        chipContent
            .background { LiquidGlassSurface(cornerRadius: 19, isInteractive: true) { Color.clear } }
    }

    // Nutzerfeedback: Button (Home/Suche/Kalender) und vor allem der
    // Richtungspfeil wirkten im Verhältnis zum Stadtnamen zu groß --
    // Icons jetzt eigens verkleinert statt am Text-Schriftgrad hängend,
    // Innenabstand/Höhe leicht reduziert, Design (Farbe, Kapselform,
    // Glas-Hintergrund) unverändert. Rotation auf 45° vereinheitlicht (siehe
    // Standort-Button in VenueMapView) statt der vorherigen 28°.
    private var chipContent: some View {
        HStack(spacing: 5) {
            Image(systemName: "location.north.fill")
                .font(.caption)
                .rotationEffect(.degrees(45))
            Text(cityStore.selectedCity?.name ?? (allowsAllCities ? "Alle Städte" : "Stadt"))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(KlangradarTheme.accent)
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    @ViewBuilder
    private func menuLabel(_ title: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            // Nutzerfeedback: Vor JEDER Option stand ein Haken, nicht nur vor
            // der ausgewählten — ein per .opacity(0) unsichtbar gemachtes
            // Checkmark-Symbol wird von SwiftUIs Menu auf manchen iOS-
            // Versionen trotzdem als eigenständiges, sichtbares Icon
            // gerendert (bekannte Eigenheit des automatischen Menu-Item-
            // Stylings). Fester Platzhalter statt unsichtbarem Icon behebt
            // das zuverlässig, ohne die Ausrichtung zu verändern.
            if selected {
                Image(systemName: "checkmark").font(.body.weight(.bold))
            } else {
                Color.clear.frame(width: 17, height: 17)
            }
            Text(title)
        }
    }
}
