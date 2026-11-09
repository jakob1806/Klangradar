// Erstellt von Claude Code (09.11.2026): Musikgeschmack aus Apple Music und
// Spotify. Gelesen wird nur auf dem Gerät (meistgehörte Künstler:innen und
// Titel); an Klangradar gehen Namen, Titel und Gewichte – nie Zugangsdaten.
import AuthenticationServices
import CryptoKit
import Foundation
import MusicKit
import UIKit

struct ListenedArtist: Sendable { var name: String; var weight: Double; var genres: [String] }
struct ListenedTrack: Sendable { var title: String; var artist: String; var composer: String?; var weight: Double }

enum MusicTasteError: LocalizedError {
    case denied, spotifyNotConfigured, cancelled, failed(String)
    var errorDescription: String? {
        switch self {
        case .denied: "Zugriff auf die Mediathek wurde nicht erlaubt (Einstellungen → Klangradar → Medien & Apple Music)."
        case .spotifyNotConfigured: "Spotify ist in dieser Version noch nicht eingerichtet."
        case .cancelled: "Abgebrochen."
        case .failed(let text): text
        }
    }
}

// MARK: - Apple Music

enum AppleMusicTaste {
    static func read() async throws -> (artists: [ListenedArtist], tracks: [ListenedTrack]) {
        let status = await MusicAuthorization.request()
        guard status == .authorized else { throw MusicTasteError.denied }
        var request = MusicLibraryRequest<Song>()
        request.limit = 500
        let songs = try await request.response().items
        var artists: [String: ListenedArtist] = [:]
        var tracks: [ListenedTrack] = []
        for song in songs {
            let plays = Double(max(1, song.playCount ?? 1))
            let weight = log2(plays + 1)
            let genres = song.genreNames
            for name in [song.artistName, song.composerName].compactMap({ $0 }) where !name.isEmpty {
                for single in name.components(separatedBy: CharacterSet(charactersIn: ",&/;")).map({ $0.trimmingCharacters(in: .whitespaces) }) where single.count > 2 {
                    var entry = artists[single] ?? ListenedArtist(name: single, weight: 0, genres: [])
                    entry.weight += weight
                    entry.genres = Array(Set(entry.genres + genres)).prefix(6).map { $0 }
                    artists[single] = entry
                }
            }
            tracks.append(ListenedTrack(title: song.title, artist: song.artistName, composer: song.composerName, weight: weight))
        }
        let topArtists = artists.values.sorted { $0.weight > $1.weight }.prefix(150)
        let topTracks = tracks.sorted { $0.weight > $1.weight }.prefix(300)
        return (Array(topArtists), Array(topTracks))
    }
}

// MARK: - Spotify (PKCE, ohne Server-Geheimnis)

@MainActor
final class SpotifyTaste: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let redirectURI = "de.klangradar.native://spotify-callback"
    private var session: ASWebAuthenticationSession?

    static var clientID: String? {
        let id = (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return id.isEmpty ? nil : id
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }

    func read() async throws -> (artists: [ListenedArtist], tracks: [ListenedTrack]) {
        guard let clientID = Self.clientID else { throw MusicTasteError.spotifyNotConfigured }
        let verifier = Self.randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge), .init(name: "scope", value: "user-top-read")
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: "de.klangradar.native") { url, error in
                if let url { continuation.resume(returning: url) }
                else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { continuation.resume(throwing: MusicTasteError.cancelled) }
                else { continuation.resume(throwing: MusicTasteError.failed("Spotify-Anmeldung fehlgeschlagen.")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw MusicTasteError.failed("Spotify hat keinen Zugang erteilt.")
        }
        let token = try await Self.exchange(code: code, verifier: verifier, clientID: clientID)
        async let artistsJSON = Self.get("https://api.spotify.com/v1/me/top/artists?limit=50&time_range=medium_term", token: token)
        async let tracksJSON = Self.get("https://api.spotify.com/v1/me/top/tracks?limit=50&time_range=medium_term", token: token)
        let (a, t) = try await (artistsJSON, tracksJSON)
        let artistItems = (a["items"] as? [[String: Any]]) ?? []
        let artists = artistItems.enumerated().compactMap { index, item -> ListenedArtist? in
            guard let name = item["name"] as? String else { return nil }
            return ListenedArtist(name: name, weight: Double(50 - index) / 5, genres: (item["genres"] as? [String]) ?? [])
        }
        let trackItems = (t["items"] as? [[String: Any]]) ?? []
        let tracks = trackItems.enumerated().compactMap { index, item -> ListenedTrack? in
            guard let title = item["name"] as? String else { return nil }
            let names = ((item["artists"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
            // Klassik auf Spotify: meist zuerst der Komponist, dann Interpret:innen.
            return ListenedTrack(title: title, artist: names.dropFirst().first ?? names.first ?? "", composer: names.first, weight: Double(50 - index) / 5)
        }
        return (artists, tracks)
    }

    private static func exchange(code: String, verifier: String, clientID: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [.init(name: "grant_type", value: "authorization_code"), .init(name: "code", value: code),
                           .init(name: "redirect_uri", value: redirectURI), .init(name: "client_id", value: clientID),
                           .init(name: "code_verifier", value: verifier)]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let token = json["access_token"] as? String else {
            throw MusicTasteError.failed("Spotify-Zugang konnte nicht bestätigt werden.")
        }
        return token
    }

    private static func get(_ url: String, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Ergebnis

struct MusicTaste: Sendable {
    struct Item: Identifiable, Sendable, Hashable {
        let id: UUID
        let title: String
        let subtitle: String?
        let imageURL: URL?
        let slug: String?
        let score: Double
    }
    var providers: [String]
    var updatedAt: Date?
    var genres: [String]
    var artistCount: Int
    var trackCount: Int
    var persons: [Item]
    var composers: [Item]
    var ensembles: [Item]
    var works: [Item]
    var events: [Item]
    var venues: [Item]

    var matchCount: Int { persons.count + ensembles.count + works.count }

    init?(json: JSONObject?) {
        guard let json else { return nil }
        func items(_ key: String, subtitle: (JSONObject) -> String? = { _ in nil }, image: String = "photo_url") -> [Item] {
            json.objects(key).compactMap { row in
                guard let id = row.uuid("id"), let title = row.string("title") else { return nil }
                return Item(id: id, title: title, subtitle: subtitle(row), imageURL: row.url(image), slug: row.string("slug"),
                            score: row.number("score") ?? 0)
            }
        }
        providers = json.strings("providers")
        updatedAt = json.date("updated_at")
        genres = json.strings("genres")
        artistCount = json.integer("artist_count") ?? 0
        trackCount = json.integer("track_count") ?? 0
        let allPersons = json.objects("persons")
        persons = items("persons")
        composers = allPersons.filter { $0.bool("is_composer") == true }.compactMap { row in
            row.uuid("id").map { Item(id: $0, title: row.string("title") ?? "", subtitle: nil, imageURL: row.url("photo_url"), slug: row.string("slug"), score: row.number("score") ?? 0) }
        }
        ensembles = items("ensembles")
        works = items("works", subtitle: { $0.string("composer") })
        events = items("events", subtitle: { row in
            let date = row.date("start_datetime").map { KlangradarDateTime.string($0, format: "EEE, d. MMM · HH:mm") }
            return [date, row.string("venue")].compactMap { $0 }.joined(separator: " · ")
        }, image: "image_url")
        venues = items("venues", subtitle: { row in row.integer("event_count").map { "\($0) passende Konzerte" } })
    }
}

extension UserRepository {
    func musicTaste(token: String) async -> MusicTaste? {
        let value: JSONObject? = try? await client.rpc("music_taste_recommendations", accessToken: token)
        return MusicTaste(json: value)
    }

    func analyzeMusicTaste(artists: [ListenedArtist], tracks: [ListenedTrack], providers: [String], token: String) async throws -> MusicTaste? {
        let artistJSON: [JSONValue] = artists.map { .object(["name": .string($0.name), "weight": .number($0.weight), "genres": .array($0.genres.map(JSONValue.string))]) }
        let trackJSON: [JSONValue] = tracks.map { track in
            var row: JSONObject = ["title": .string(track.title), "artist": .string(track.artist), "weight": .number(track.weight)]
            if let composer = track.composer { row["composer"] = .string(composer) }
            return .object(row)
        }
        let value: JSONObject? = try await client.rpc("music_taste_analyze", parameters: [
            "p_artists": .array(artistJSON), "p_tracks": .array(trackJSON), "p_providers": .array(providers.map(JSONValue.string))
        ], accessToken: token)
        return MusicTaste(json: value)
    }

    func disconnectMusicTaste(token: String) async {
        let _: JSONValue? = try? await client.rpc("music_taste_disconnect", accessToken: token)
    }
}
