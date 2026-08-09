import Foundation

struct APIConfiguration: Sendable {
    let supabaseURL: URL
    let supabaseAnonKey: String

    static func load(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) -> APIConfiguration? {
        let environment = processInfo.environment
        let environmentURL = environment["SUPABASE_URL"]
        let environmentKey = environment["SUPABASE_ANON_KEY"]

        if let configuration = make(url: environmentURL, key: environmentKey) {
            return configuration
        }

        guard
            let secretsURL = bundle.url(forResource: "Secrets", withExtension: "plist"),
            let data = try? Data(contentsOf: secretsURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
            ) as? [String: Any]
        else {
            return nil
        }

        return make(
            url: plist["SUPABASE_URL"] as? String,
            key: plist["SUPABASE_ANON_KEY"] as? String
        )
    }

    private static func make(url: String?, key: String?) -> APIConfiguration? {
        guard
            let url,
            let key,
            !key.isEmpty,
            let baseURL = URL(string: url),
            ["https", "http"].contains(baseURL.scheme?.lowercased())
        else {
            return nil
        }

        return APIConfiguration(
            supabaseURL: baseURL,
            supabaseAnonKey: key
        )
    }
}
