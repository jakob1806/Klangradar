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
                Button { showsCitySwitcher = true } label: { toolbarChipLabel }
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
        } label: { mapChipLabel }
    }

    // Nutzerfeedback: Städte-Chip auf der Karte soll denselben Glas-Stil wie
    // "Filter" und der Standort-Button auf VenueMapView zeigen — beide
    // stehen frei über der Karte (kein Toolbar-Kontext) und bekommen deshalb
    // KEIN automatisches System-Glas, anders als unten bei toolbarChipLabel.
    private var mapChipLabel: some View {
        chipContent
            .background { LiquidGlassSurface(cornerRadius: 19, isInteractive: true) { Color.clear } }
    }

    // Nutzerfeedback: "doppelter Liquid-Glass-Effekt" auf Home/Suche/Kalender
    // — dieser Chip steckt dort in einem ToolbarItem, das iOS 26 bereits
    // automatisch mit eigenem Liquid Glass umgibt (siehe RootTabView/
    // SearchView). Ein zusätzliches, manuelles LiquidGlassSurface hier
    // legte eine zweite Glasschicht darüber. Auf iOS 26 deshalb bewusst KEIN
    // eigener Hintergrund — das System-Glas des Toolbars reicht; nur der
    // Material-Fallback für iOS 17–25 (kein automatisches Toolbar-Glas dort)
    // bekommt weiterhin einen manuellen Hintergrund.
    @ViewBuilder
    private var toolbarChipLabel: some View {
        if #available(iOS 26.0, *) {
            chipContent
        } else {
            chipContent
                .background(.regularMaterial, in: .capsule)
        }
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
            // Nutzerfeedback: Die ausgewählte Zeile war zusätzlich eingerückt
            // ("München" stand weiter rechts als die anderen Städte). Grund:
            // SwiftUIs Menu behandelt ein Image(systemName: "checkmark") als
            // eigenes Auswahl-Symbol und reserviert dafür ZUSÄTZLICH zu
            // unserem manuellen HStack-Eintrag eigenen Platz — nur bei der
            // Zeile, die dieses SF-Symbol tatsächlich enthält. Ein reines
            // Text-Glyph statt des Systemsymbols umgeht diese Sonderbehandlung
            // vollständig, sieht aber identisch aus.
            if selected {
                Text("✓").font(.body.weight(.bold))
            } else {
                Color.clear.frame(width: 17, height: 17)
            }
            Text(title)
        }
    }
}
