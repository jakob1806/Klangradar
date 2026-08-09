import Foundation

struct SupabaseRESTClient: Sendable {
    private let configuration: APIConfiguration
    private let httpClient: any HTTPClient
    private let decoder: JSONDecoder

    init(
        configuration: APIConfiguration,
        httpClient: any HTTPClient = URLSessionHTTPClient()
    ) {
        self.configuration = configuration
        self.httpClient = httpClient

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func publicStorageURL(bucket: String, path: String) -> URL {
        configuration.supabaseURL
            .appendingPathComponent("storage/v1/object/public")
            .appendingPathComponent(bucket)
            .appendingPathComponent(path)
    }

    func get<Response: Decodable & Sendable>(
        table: String,
        queryItems: [URLQueryItem],
        accessToken: String? = nil
    ) async throws -> Response {
        guard var components = URLComponents(
            url: configuration.supabaseURL
                .appendingPathComponent("rest/v1")
                .appendingPathComponent(table),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }

        components.queryItems = queryItems
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        let request = authorizedRequest(url: url, accessToken: accessToken)
        let data = try await perform(request)

        return try decoder.decode(Response.self, from: data)
    }

    func rpc<Response: Decodable & Sendable>(
        _ function: String,
        parameters: JSONObject = [:],
        accessToken: String? = nil
    ) async throws -> Response {
        let url = configuration.supabaseURL
            .appendingPathComponent("rest/v1/rpc")
            .appendingPathComponent(function)
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(parameters)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try decoder.decode(Response.self, from: try await perform(request))
    }

    func insert(
        table: String,
        values: JSONObject,
        accessToken: String,
        returning: Bool = false
    ) async throws -> [JSONObject] {
        let url = configuration.supabaseURL
            .appendingPathComponent("rest/v1")
            .appendingPathComponent(table)
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(values)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            returning ? "return=representation" : "return=minimal",
            forHTTPHeaderField: "Prefer"
        )
        let data = try await perform(request)
        return data.isEmpty ? [] : try decoder.decode([JSONObject].self, from: data)
    }

    func upsert(
        table: String,
        values: JSONObject,
        accessToken: String,
        conflictColumns: String? = nil
    ) async throws {
        var components = URLComponents(
            url: configuration.supabaseURL
                .appendingPathComponent("rest/v1")
                .appendingPathComponent(table),
            resolvingAgainstBaseURL: false
        )
        if let conflictColumns {
            components?.queryItems = [URLQueryItem(name: "on_conflict", value: conflictColumns)]
        }
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(values)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await perform(request)
    }

    func delete(
        table: String,
        filters: [URLQueryItem],
        accessToken: String
    ) async throws {
        guard var components = URLComponents(
            url: configuration.supabaseURL
                .appendingPathComponent("rest/v1")
                .appendingPathComponent(table),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidURL }
        components.queryItems = filters
        guard let url = components.url else { throw APIError.invalidURL }
        var request = authorizedRequest(url: url, accessToken: accessToken)
        request.httpMethod = "DELETE"
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await perform(request)
    }

    private func authorizedRequest(url: URL, accessToken: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(accessToken ?? configuration.supabaseAnonKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await httpClient.data(for: request)
        guard 200..<300 ~= response.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
            throw APIError.httpStatus(response.statusCode, message)
        }
        return data
    }
}
