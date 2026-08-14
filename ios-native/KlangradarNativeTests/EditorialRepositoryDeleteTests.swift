import XCTest
@testable import KlangradarNative

/// Deckt die neuen delete_*-RPC-Aufrufe ab (Nutzervorgabe "der admin darf
/// veranstaltungen, ensembles, personen, venues usw. löschen") — kein
/// Netzwerkzugriff nötig, ein HTTPClient-Test-Double reicht, weil
/// SupabaseRESTClient httpClient injizierbar macht.
private final class RecordingHTTPClient: HTTPClient, @unchecked Sendable {
    // Löschen macht zwei Aufrufe (die delete_*-RPC, danach ein
    // system_logs-Insert für die Protokollierung) — alle mitschneiden statt
    // nur den letzten, sonst überschreibt das Logging-Insert den eigentlich
    // zu prüfenden RPC-Aufruf.
    private(set) var requests: [URLRequest] = []
    var statusCode = 200

    // Unterschiedliche Aufrufer decodieren die Antwort unterschiedlich:
    // die delete_*-RPCs erwarten Bool ("true"), update_venue erwartet ein
    // einzelnes Objekt (liefert die geänderte venues-Zeile), insert() IMMER
    // ein Array (Supabase gibt bei Inserts eine Zeilenliste zurück),
    // update()/delete() werten die Antwort gar nicht aus. Ein einzelner
    // literaler Antwort-Body würde je nach Pfad an einer der Decodierungen
    // scheitern — daher pfadabhängig plausible Formen liefern.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        let body: Data
        if path.contains("/rpc/delete_") {
            body = Data("true".utf8)
        } else if path.contains("/rpc/") {
            body = Data("{}".utf8)
        } else {
            body = Data("[{}]".utf8)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    func request(matchingPathSuffix suffix: String) -> URLRequest? {
        requests.first { $0.url?.path.hasSuffix(suffix) == true }
    }
}

final class EditorialRepositoryDeleteTests: XCTestCase {
    private func makeRepository(_ client: RecordingHTTPClient) -> EditorialRepository {
        let configuration = APIConfiguration(supabaseURL: URL(string: "https://example.supabase.co")!, supabaseAnonKey: "anon")
        return EditorialRepository(client: SupabaseRESTClient(configuration: configuration, httpClient: client))
    }

    func testDeleteEntityCallsDeleteVenueRPCWithVenueID() async throws {
        let recorder = RecordingHTTPClient()
        let repository = makeRepository(recorder)
        let venueID = UUID()
        let entity = EditorialEntity(id: venueID, kind: .venue, title: "Nationaltheater", subtitle: nil, editableSubtitle: nil, description: nil, imageURL: nil, composerID: nil)

        try await repository.deleteEntity(entity, actor: UUID(), token: "token")

        let request = try XCTUnwrap(recorder.request(matchingPathSuffix: "/rpc/delete_venue"))
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(JSONObject.self, from: body)
        XCTAssertEqual(decoded.string("p_venue_id"), venueID.uuidString)
    }

    func testDeleteEntityRejectsWorkKindWithoutNetworkCall() async {
        let recorder = RecordingHTTPClient()
        let repository = makeRepository(recorder)
        let entity = EditorialEntity(id: UUID(), kind: .work, title: "Zauberflöte", subtitle: nil, editableSubtitle: nil, description: nil, imageURL: nil, composerID: nil)

        do {
            try await repository.deleteEntity(entity, actor: UUID(), token: "token")
            XCTFail("Werke dürfen hier nicht löschbar sein")
        } catch is EditorialError {
            XCTAssertTrue(recorder.requests.isEmpty, "Werk-Löschung darf keinen Netzwerkaufruf auslösen")
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)")
        }
    }

    func testDeleteEventCallsDeleteEventRPCWithEventID() async throws {
        let recorder = RecordingHTTPClient()
        let repository = makeRepository(recorder)
        let event = EditorialEvent(id: UUID(), slug: "test", title: "Testkonzert", subtitle: nil, startDate: .now, venueID: UUID(), venueName: "Testsaal", imageURL: nil, status: "scheduled")

        try await repository.deleteEvent(event, actor: UUID(), token: "token")

        let request = try XCTUnwrap(recorder.request(matchingPathSuffix: "/rpc/delete_event"))
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(JSONObject.self, from: body)
        XCTAssertEqual(decoded.string("p_event_id"), event.id.uuidString)
    }

    // MARK: - Feldparität mit den Web-Admin-Formularen (venue-/person-/
    // ensemble-/event-form.tsx) — deckt die neuen update*()-Funktionen ab.

    func testUpdateVenueCallsUpdateVenueRPCWithAddressAndCoordinates() async throws {
        let recorder = RecordingHTTPClient()
        let repository = makeRepository(recorder)
        let venueID = UUID()
        let entity = EditorialEntity(id: venueID, kind: .venue, title: "Altes Haus", subtitle: nil, editableSubtitle: nil, description: nil, imageURL: nil, composerID: nil)

        try await repository.updateVenue(
            entity: entity, name: "Nationaltheater", slug: "nationaltheater", description: "Oper",
            addressStreet: "Max-Joseph-Platz 2", addressZip: "80539", addressCity: "München",
            latitude: 48.1397, longitude: 11.5764, capacity: 2100, websiteURL: "https://staatsoper.de", imageURL: "",
            actor: UUID(), token: "token"
        )

        let request = try XCTUnwrap(recorder.request(matchingPathSuffix: "/rpc/update_venue"))
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(JSONObject.self, from: body)
        XCTAssertEqual(decoded.string("p_id"), venueID.uuidString)
        XCTAssertEqual(decoded.string("p_address_street"), "Max-Joseph-Platz 2")
        XCTAssertEqual(decoded.number("p_lat"), 48.1397)
        XCTAssertEqual(decoded.number("p_lng"), 11.5764)
        XCTAssertEqual(decoded.number("p_capacity"), 2100)
    }

    func testUpdatePersonDetailsComposesFullNameAndPatchesPersonsTable() async throws {
        let recorder = RecordingHTTPClient()
        let repository = makeRepository(recorder)
        let personID = UUID()
        let entity = EditorialEntity(id: personID, kind: .person, title: "Alt", subtitle: nil, editableSubtitle: nil, description: nil, imageURL: nil, composerID: nil)

        try await repository.updatePersonDetails(
            entity: entity, firstName: "Anna", middleName: "", lastName: "Netrebko", slug: "anna-netrebko",
            instrument: "Sopran", biographyDe: "", imageURL: "",
            roles: ["solist"], nationality: "Russland", birthDate: "1971-09-18", deathDate: "", isDeceased: false,
            memberOfEnsembleID: nil, websiteURL: "", isVerified: true, actor: UUID(), token: "token"
        )

        let request = try XCTUnwrap(recorder.request(matchingPathSuffix: "/rest/v1/persons"))
        XCTAssertEqual(request.httpMethod, "PATCH")
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(JSONObject.self, from: body)
        XCTAssertEqual(decoded.string("full_name"), "Anna Netrebko")
        XCTAssertEqual(decoded.string("last_name"), "Netrebko")
        XCTAssertEqual(decoded.strings("roles"), ["solist"])
        XCTAssertEqual(decoded.bool("is_verified"), true)
    }

    func testUpdateEnsembleDetailsPatchesEnsemblesTable() async throws {
        let recorder = RecordingHTTPClient()
        let repository = makeRepository(recorder)
        let venueID = UUID()
        let entity = EditorialEntity(id: UUID(), kind: .ensemble, title: "BRSO", subtitle: nil, editableSubtitle: nil, description: nil, imageURL: nil, composerID: nil)

        try await repository.updateEnsembleDetails(
            entity: entity, slug: "brso", type: "orchester", foundedYear: 1949, memberCount: 120,
            homeVenueID: venueID, parentEnsembleID: nil, websiteURL: "https://br.de", isVerified: true,
            actor: UUID(), token: "token"
        )

        let request = try XCTUnwrap(recorder.request(matchingPathSuffix: "/rest/v1/ensembles"))
        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(JSONObject.self, from: body)
        XCTAssertEqual(decoded.string("type"), "orchester")
        XCTAssertEqual(decoded.number("founded_year"), 1949)
        XCTAssertEqual(decoded.string("home_venue_id"), venueID.uuidString)
    }

    func testUpdateEventDetailsPatchesEventsAndSyncsGenres() async throws {
        let recorder = RecordingHTTPClient()
        let repository = makeRepository(recorder)
        let event = EditorialEvent(id: UUID(), slug: "test", title: "Testkonzert", subtitle: nil, startDate: .now, venueID: UUID(), venueName: "Testsaal", imageURL: nil, status: "scheduled")
        let genreID = UUID()

        try await repository.updateEventDetails(
            event: event, descriptionDe: "Ein Abend", durationMinutes: 90, hasIntermission: true,
            organizerID: nil, genreIDs: [genreID], priceMin: 10, priceMax: 50, isFree: false,
            ticketURL: "https://tickets.example", remainingTicketsStatus: "available", doorsInfo: "19:00",
            ageRestriction: "", discountInfo: "", presaleFeeInfo: "", status: "scheduled",
            actor: UUID(), token: "token"
        )

        let patchRequest = try XCTUnwrap(recorder.request(matchingPathSuffix: "/rest/v1/events"))
        XCTAssertEqual(patchRequest.httpMethod, "PATCH")
        let patchBody = try XCTUnwrap(patchRequest.httpBody)
        let decodedPatch = try JSONDecoder().decode(JSONObject.self, from: patchBody)
        XCTAssertEqual(decodedPatch.integer("duration_minutes"), 90)
        XCTAssertEqual(decodedPatch.bool("has_intermission"), true)

        let deleteGenres = recorder.requests.first { $0.httpMethod == "DELETE" && $0.url?.path.hasSuffix("/rest/v1/event_genres") == true }
        XCTAssertNotNil(deleteGenres, "Bestehende Genre-Zuordnungen müssen vor dem Neueinfügen gelöscht werden")

        let insertGenre = recorder.requests.first { $0.httpMethod == "POST" && $0.url?.path.hasSuffix("/rest/v1/event_genres") == true }
        let insertBody = try XCTUnwrap(insertGenre?.httpBody)
        let decodedInsert = try JSONDecoder().decode(JSONObject.self, from: insertBody)
        XCTAssertEqual(decodedInsert.string("genre_id"), genreID.uuidString)
    }
}
