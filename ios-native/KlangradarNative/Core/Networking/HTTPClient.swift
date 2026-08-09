import Foundation

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, httpResponse)
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Der Server hat keine gültige Antwort geliefert."
        case let .httpStatus(status, message):
            return "Serverfehler \(status): \(message)"
        case .invalidURL:
            return "Die API-Adresse ist ungültig."
        }
    }
}
