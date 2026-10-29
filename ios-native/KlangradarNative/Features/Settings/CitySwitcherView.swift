import SwiftUI

/// "Stadt wechseln" — Nutzeranfrage: Städteauswahl analog zum Flutter-
/// Die gestaltete SwiftUI-Auswahl für Home, Suche, Kalender und Profil.
/// Sie ist bewusst kein technisches List-Menü: die Stadt ist eine zentrale
/// Einstellung und soll sich wie ein eigener Klangradar-Bereich anfühlen.
struct CitySwitcherView: View {
    @ObservedObject var cityStore: CityStore
    var allowsAllCities = false
    /// "Alle Städte" gilt nur im aufrufenden Tab (z. B. Kalender) und ändert
    /// die globale Stadt nicht; eine konkrete Stadt gilt überall.
    var allCitiesSelection: Binding<Bool>? = nil
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
                    if let allCitiesSelection {
                        cityRow(name: "Alle Städte", subtitle: "Nur in diesem Bereich", isSelected: allCitiesSelection.wrappedValue) {
                            allCitiesSelection.wrappedValue = true
                            dismiss()
                        }
                    }
                    ForEach(displayCities) { city in
                        cityRow(
                            name: city.name,
                            subtitle: countryLabel(for: city),
                            isSelected: allCitiesSelection?.wrappedValue != true && cityStore.selectedCity?.id == city.id
                        ) {
                            allCitiesSelection?.wrappedValue = false
                            cityStore.select(city)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .background(KlangradarBackground().ignoresSafeArea())
        .toolbar {
            if embedsNavigationStack {
                doneToolbarItem
            }
        }
        // Nutzerfeedback: "Fertig" hatte kein Liquid Glass um sich herum --
        // .toolbarBackground(.hidden) hier (unbedingt, auch auf iOS 26)
        // unterdrückte auch die automatische Glas-Kapsel des
        // .confirmationAction-Buttons selbst. Diese Seite hat anders als
        // Home/Suche/Kalender keinen eigenen ToolbarItem-Chip, der mit dem
        // System-Glas kollidieren könnte -- kein Grund, es hier zu verstecken.
        .navigationTitle(embedsNavigationStack ? "" : "Stadt wechseln")
        .navigationBarTitleDisplayMode(.inline)
        .task { if cityStore.activeCities.isEmpty { await cityStore.load() } }
    }

    // 29.10.2026: .buttonStyle(.glass) in der Toolbar legte ein zweites Glas
    // in die Kapsel der Toolbar; die Breite reichte nur für "Fe…". Jetzt
    // eigenes Glas mit fester Breite, das System-Glas ist ausgeblendet.
    @ToolbarContentBuilder
    private var doneToolbarItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .confirmationAction) { doneButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .confirmationAction) { doneButton }
        }
    }

    private var doneButton: some View {
        Button { dismiss() } label: {
            Text("Fertig")
                .font(.body.weight(.semibold))
                .foregroundStyle(KlangradarTheme.accent)
                .fixedSize()
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background { LiquidGlassSurface(cornerRadius: 19, isInteractive: true) { Color.clear } }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
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
    /// Lokale "Alle Städte"-Auswahl des Tabs (nil = Option nicht anbieten).
    /// Vorher setzte "Alle Städte" die globale Stadt auf nil — alle anderen
    /// Tabs zeigten dann nur noch "Stadt".
    var allCitiesSelection: Binding<Bool>? = nil
    var isMapMenu = false
    @State private var showsCitySwitcher = false

    private var showsAllCities: Bool { allCitiesSelection?.wrappedValue == true }

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
            CitySwitcherView(cityStore: cityStore, allCitiesSelection: allCitiesSelection)
                // Nutzerfeedback per Screenshot: das Sheet zeigte links/
                // rechts/unten Rand mit sichtbarem Hintergrund dahinter statt
                // randlos zu sein — dieselbe Ursache/derselbe Fix wie beim
                // Klangradar-KI-Popup (siehe RootTabView.CoachSheetPresentation):
                // ohne explizites .page-Sizing zeigt iOS 26 hier die
                // freischwebende "Form"-Karte statt eines randlosen Sheets.
                .modifier(EdgeToEdgeSheetSizing())
        }
        .accessibilityLabel("Stadt auswählen")
    }

    private var mapMenu: some View {
        Menu {
            if let allCitiesSelection {
                Button {
                    allCitiesSelection.wrappedValue = true
                } label: {
                    menuLabel("Alle Städte", selected: showsAllCities)
                }
            }
            ForEach(cityStore.activeCities) { city in
                Button {
                    allCitiesSelection?.wrappedValue = false
                    cityStore.select(city)
                } label: {
                    menuLabel(city.name, selected: !showsAllCities && cityStore.selectedCity?.id == city.id)
                }
            }
        } label: { chipLabel }
    }

    // Nutzerfeedback (zweiter Anlauf): Auf iOS 26 den eigenen Hintergrund
    // ganz wegzulassen war die falsche Lösung für "doppeltes Glas" im
    // Toolbar (Home/Suche/Kalender) — ohne .sharedBackgroundVisibility(.hidden)
    // auf dem umgebenden ToolbarItem (siehe Home/SearchView/
    // EventCalendarView) spannt sich das AUTOMATISCHE System-Glas des
    // Toolbars über die GANZE Zeile, inklusive des Titels links — sichtbar
    // als eine große, geteilte Glasfläche statt des gewünschten einzelnen
    // kleinen Chips. Der richtige Fix: automatisches Glas dort unterdrücken,
    // dieses eigene, in sich geschlossene Glas behalten — exakt wie beim
    // Standort-/Filter-Button auf der Karte, wo kein Toolbar-Kontext
    // existiert und deshalb auch kein automatisches Glas kollidieren kann.
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
            Text(showsAllCities ? "Alle Städte" : (cityStore.selectedCity?.name ?? "Stadt"))
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(KlangradarTheme.accent)
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    // Nutzerfeedback (zweiter Anlauf): Das Text-Glyph landete als eigene
    // Menüzeile OBERHALB des zugehörigen Stadtnamens statt daneben — ein
    // manuell gebautes HStack innerhalb eines Menu-Button-Labels wird von
    // SwiftUI nicht zuverlässig als eine einzelne, inline angeordnete Zeile
    // behandelt. Der native, dafür vorgesehene Weg ist Label mit separatem
    // icon:-Builder: Menu reserviert für JEDE Zeile denselben Icon-Platz
    // (einheitlicher Einzug für alle Städte, wie gewünscht) und füllt ihn
    // nur bei der ausgewählten Zeile mit dem Haken — leer sonst, keine
    // eigene Zeile, kein Extra-Einzug.
    @ViewBuilder
    private func menuLabel(_ title: String, selected: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }
}

/// Ohne explizites .page-Sizing zeigt iOS 26 ein detentloses Sheet ohne
/// eigene Höhenbegrenzung trotzdem als freischwebende "Form"-Karte mit
/// Rand auf allen Seiten (gleiche Ursache wie beim Klangradar-KI-Popup,
/// siehe RootTabView.CoachSheetPresentation) -- .page erzwingt randlose
/// Darstellung.
private struct EdgeToEdgeSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}
