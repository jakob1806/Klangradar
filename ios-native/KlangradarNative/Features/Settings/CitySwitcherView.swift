import SwiftUI

/// "Stadt wechseln" — Nutzeranfrage: Städteauswahl analog zum Flutter-
/// Pendant (CityPicker in map_screen.dart), aber als eigener,
/// dedizierter Screen statt eines Bottom-Sheets, erreichbar von Profil/
/// Karte aus. `nil` in der Liste steht für "Alle Städte" (kein Filter).
struct CitySwitcherView: View {
    @ObservedObject var cityStore: CityStore
    @Environment(\.dismiss) private var dismiss

    @State private var isLocating = false
    @State private var locationError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(KlangradarTheme.accent)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stadt wechseln")
                            .font(.largeTitle.bold())
                        Text("Du kannst deine Stadt jederzeit schnell ändern. Personen, Ensembles und Werke bleiben stadtübergreifend verfügbar.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await recommendByLocation() }
                    } label: {
                        HStack {
                            if isLocating {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "location.fill")
                            }
                            Text("Stadt anhand meines Standorts empfehlen")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(KlangradarTheme.accent)
                    .background(KlangradarTheme.accent.opacity(0.14), in: .capsule)
                    .disabled(isLocating)

                    if let locationError {
                        Text(locationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    VStack(spacing: 0) {
                        cityRow(name: "Alle Städte", subtitle: nil, isSelected: cityStore.selectedCity == nil) {
                            cityStore.select(nil)
                        }
                        ForEach(cityStore.activeCities) { city in
                            Divider().padding(.leading, 20)
                            cityRow(
                                name: city.name,
                                subtitle: countryLabel(for: city),
                                isSelected: cityStore.selectedCity?.id == city.id
                            ) {
                                cityStore.select(city)
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(20)
            }
            .background(KlangradarBackground().ignoresSafeArea())
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
        Button(action: action) {
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
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
