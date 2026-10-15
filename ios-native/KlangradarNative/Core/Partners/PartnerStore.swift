import Foundation

/// Affiliate-Regel aus `affiliate_rules` (Migration 000026).
struct AffiliateRule: Sendable, Equatable {
    let hostSuffix: String
    let urlTemplate: String?
    let appendParams: [String: String]

    /// nil = Regel passt nicht auf die Adresse.
    func rewrite(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(), host == hostSuffix || host.hasSuffix("." + hostSuffix) else { return nil }
        var target = url
        if !appendParams.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = components.queryItems ?? []
            for (key, value) in appendParams.sorted(by: { $0.key < $1.key }) where !items.contains(where: { $0.name == key }) {
                items.append(URLQueryItem(name: key, value: value))
            }
            components.queryItems = items
            target = components.url ?? url
        }
        if let urlTemplate {
            let encoded = target.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? target.absoluteString
            return URL(string: urlTemplate.replacingOccurrences(of: "{url}", with: encoded))
        }
        return target
    }
}

/// Plus-Vorteil aus `partner_offers`.
struct PartnerOffer: Identifiable, Sendable, Hashable {
    let id: UUID
    let partnerName: String
    let title: String
    let description: String?
    let code: String?
    let url: URL?
    let validUntil: Date?
}

/// Lädt Affiliate-Regeln und Partnerangebote einmal pro Start (öffentlich
/// lesbar, keine Anmeldung nötig) und schreibt Ticketlinks um. Ohne Regeln
/// bleiben Links unverändert.
@MainActor
final class PartnerStore: ObservableObject {
    static let shared = PartnerStore()
    @Published private(set) var offers: [PartnerOffer] = []
    private(set) var rules: [AffiliateRule] = []
    private var client: SupabaseRESTClient?
    private var loaded = false

    func configure(client: SupabaseRESTClient?) {
        self.client = client
        Task { await load() }
    }

    func load() async {
        guard let client, !loaded else { return }
        loaded = true
        async let ruleRows: [JSONObject] = (try? client.get(table: "affiliate_rules", queryItems: [
            URLQueryItem(name: "select", value: "host_suffix,url_template,append_params"),
            URLQueryItem(name: "active", value: "eq.true")
        ])) ?? []
        async let offerRows: [JSONObject] = (try? client.get(table: "partner_offers", queryItems: [
            URLQueryItem(name: "select", value: "id,partner_name,title,description,code,url,valid_until"),
            URLQueryItem(name: "order", value: "sort_order.asc,created_at.desc")
        ])) ?? []
        rules = await ruleRows.compactMap { row in
            guard let host = row.string("host_suffix")?.lowercased(), !host.isEmpty else { return nil }
            var params: [String: String] = [:]
            if let object = row.object("append_params") {
                for (key, value) in object { if case let .string(text) = value { params[key] = text } }
            }
            return AffiliateRule(hostSuffix: host, urlTemplate: row.string("url_template"), appendParams: params)
        }
        offers = await offerRows.compactMap { row in
            guard let id = row.string("id").flatMap(UUID.init(uuidString:)), let partner = row.string("partner_name"), let title = row.string("title") else { return nil }
            return PartnerOffer(
                id: id, partnerName: partner, title: title, description: row.string("description"), code: row.string("code"),
                url: row.string("url").flatMap(URL.init(string:)), validUntil: row.string("valid_until").flatMap(FlexibleDateParser.date(from:))
            )
        }
    }

    /// Umgeschriebene Adresse und ob es ein Partnerlink ist (Kennzeichnungspflicht).
    func ticketLink(for url: URL) -> (url: URL, isAffiliate: Bool) {
        for rule in rules { if let rewritten = rule.rewrite(url) { return (rewritten, true) } }
        return (url, false)
    }
}
