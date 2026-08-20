import MapKit
import PhotosUI
import SwiftUI

/// Punkt 20, Venue-Erstellung: Kartensuche/GPS für Adresse+Koordinaten statt
/// manueller Lat/Lng-Eingabe, eine nicht-blockierende Dublettenwarnung
/// während des Tippens (harte Sperre passiert zusätzlich serverseitig beim
/// Speichern, siehe EditorialRepository.createVenue), Bild-Upload wie bei
/// den anderen Entitätstypen. `onCreated` liefert die neue/gefundene Venue
/// direkt zurück, damit ein aufrufender Event-Editor sie sofort zuweisen
/// kann ("Event-Zuweisung").
struct EditorialCreateVenueView: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let onCreated: (EditorialOption) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var addressStreet = ""
    @State private var addressZip = ""
    @State private var addressCity = "München"
    @State private var description = ""
    @State private var websiteURL = ""
    @State private var capacityText = ""
    @State private var imageURL = ""
    @State private var pendingImageData: Data?

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var addressQuery = ""
    @StateObject private var locationSearch = EditorialLocationSearch()
    @State private var isResolvingSuggestion = false
    @State private var isLocating = false

    @State private var duplicateCandidates: [EditorialOption] = []
    @State private var duplicateCheckTask: Task<Void, Never>?

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EditorialModeBanner(compact: true)
                }

                Section("Kartensuche") {
                    TextField("Name oder Adresse suchen", text: $addressQuery)
                        .textInputAutocapitalization(.words)
                        .onChange(of: addressQuery) { _, query in locationSearch.update(query: query) }
                    ForEach(locationSearch.suggestions, id: \.self) { suggestion in
                        Button {
                            Task { await applySuggestion(suggestion) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(suggestion.title).foregroundStyle(.primary)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        if isLocating { ProgressView() }
                        else { Label("Meinen Standort verwenden", systemImage: "location.fill") }
                    }
                    .disabled(isLocating)
                }

                if let coordinate {
                    Section {
                        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))) {
                            Marker(name.isEmpty ? "Neue Venue" : name, coordinate: coordinate)
                        }
                        .frame(height: 160)
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Section("Stammdaten") {
                    TextField("Name", text: $name)
                        .onChange(of: name) { _, newValue in scheduleDuplicateCheck(newValue) }
                    if !duplicateCandidates.isEmpty {
                        Label("Ähnliche Einträge vorhanden: \(duplicateCandidates.map(\.title).joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    TextField("Straße & Hausnummer", text: $addressStreet)
                    TextField("PLZ", text: $addressZip).keyboardType(.numberPad)
                    TextField("Stadt", text: $addressCity)
                    TextField("Kapazität", text: $capacityText).keyboardType(.numberPad)
                    TextField("Website", text: $websiteURL).textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("Beschreibung", text: $description, axis: .vertical).lineLimit(3...8)
                }

                Section("Bild") {
                    TextField("Bild-URL (optional)", text: $imageURL).textInputAutocapitalization(.never).keyboardType(.URL)
                    EditorialImagePickerButtons(
                        onImages: { pendingImageData = $0.first },
                        onError: { errorMessage = $0 },
                        allowsMultipleSelection: false
                    )
                    if pendingImageData != nil {
                        Label("Bild ausgewählt", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }

                Section {
                    Button {
                        Task { await create() }
                    } label: {
                        Label("Venue anlegen", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(KlangradarTheme.accent)
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || coordinate == nil)
                } footer: {
                    Text(coordinate == nil ? "Bitte zuerst über die Kartensuche oder GPS eine Position wählen." : "Der neue Eintrag wird sofort zentral gespeichert.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(EditorialBackground())
            .navigationTitle("Venue anlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .overlay { if isSaving { ProgressView() } }
            .alert("Venue nicht angelegt", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    @MainActor private func applySuggestion(_ suggestion: MKLocalSearchCompletion) async {
        isResolvingSuggestion = true; defer { isResolvingSuggestion = false }
        guard let item = await locationSearch.resolve(suggestion) else { return }
        coordinate = item.placemark.coordinate
        if name.isEmpty { name = suggestion.title }
        if let street = item.placemark.thoroughfare {
            addressStreet = [street, item.placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        }
        if let zip = item.placemark.postalCode { addressZip = zip }
        if let city = item.placemark.locality { addressCity = city }
        addressQuery = ""
    }

    @MainActor private func useCurrentLocation() async {
        isLocating = true; defer { isLocating = false }
        do {
            let fetcher = EditorialCurrentLocationFetcher()
            let location = try await fetcher.currentLocation()
            coordinate = location.coordinate
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
            if let placemark = placemarks?.first {
                if let street = placemark.thoroughfare {
                    addressStreet = [street, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
                }
                if let zip = placemark.postalCode { addressZip = zip }
                if let city = placemark.locality { addressCity = city }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func scheduleDuplicateCheck(_ query: String) {
        duplicateCheckTask?.cancel()
        duplicateCheckTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let token = auth.accessToken else { return }
            let matches = (try? await repository.findMatchingVenues(name: query, token: token)) ?? []
            if !Task.isCancelled { duplicateCandidates = matches }
        }
    }

    @MainActor private func create() async {
        guard let token = auth.accessToken, let actor = auth.userID, let coordinate else { return }
        isSaving = true; defer { isSaving = false }
        do {
            var effectiveImageURL = imageURL
            // Bild braucht die Origin-ID zum Hochladen — kann erst NACH der
            // Venue-Anlage passieren, daher hier nur die URL, das
            // tatsächliche Bild folgt unten.
            let entity = try await repository.createVenue(
                name: name, addressStreet: addressStreet, addressZip: addressZip, addressCity: addressCity,
                description: description, latitude: coordinate.latitude, longitude: coordinate.longitude,
                capacity: Int(capacityText), websiteURL: websiteURL, imageURL: effectiveImageURL,
                actor: actor, token: token
            )
            if let pendingImageData {
                let uploadedURL = try await repository.uploadEditorialImage(data: pendingImageData, originType: "venue-profiles", originID: entity.id, token: token)
                effectiveImageURL = uploadedURL.absoluteString
                try await repository.updateVenue(
                    entity: entity, name: name, slug: entity.slug ?? "", description: description,
                    addressStreet: addressStreet, addressZip: addressZip, addressCity: addressCity,
                    latitude: coordinate.latitude, longitude: coordinate.longitude, capacity: Int(capacityText),
                    websiteURL: websiteURL, imageURL: effectiveImageURL, actor: actor, token: token
                )
            }
            RecentlyEditedStore.shared.record(kind: .venue, id: entity.id, title: entity.title)
            onCreated(EditorialOption(id: entity.id, title: entity.title, subtitle: nil))
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
