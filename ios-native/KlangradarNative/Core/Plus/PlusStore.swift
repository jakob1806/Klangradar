import Foundation
import StoreKit

/// Klangradar Plus über Apples In-App-Kauf (StoreKit 2). Die Freischaltung
/// wird lokal aus den von Apple signierten Transaktionen abgeleitet
/// (`Transaction.currentEntitlements`). Zusätzlich zählt eine serverseitige
/// Freischaltung (`my_plus_status`, z. B. per eingelöstem Code – Nachtrag
/// Claude Code 27.10.2026). Plus ist aktiv, wenn eins von beiden zutrifft.
@MainActor
final class PlusStore: ObservableObject {
    static let shared = PlusStore()
    static let productIDs = ["de.klangradar.plus.yearly", "de.klangradar.plus.monthly"]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPlus = false
    @Published private(set) var isRedeeming = false
    private var storeKitPlus = false
    private var storeKitExpiry: Date?
    private var serverPlus = false
    private var serverExpiry: Date?
    private var client: SupabaseRESTClient?
    private weak var auth: AuthStore?
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    /// Limits greifen nur, wenn Plus tatsächlich kaufbar ist — sonst würde
    /// man Nutzer ohne Ausweg blockieren (z. B. vor Freischaltung in App Store Connect).
    var isOfferAvailable: Bool { !products.isEmpty }
    var enforcesLimits: Bool { isOfferAvailable && !isPlus }

    private var updatesTask: Task<Void, Never>?

    func configure(client: SupabaseRESTClient?, auth: AuthStore) {
        self.client = client
        self.auth = auth
    }

    /// Server-Freischaltung nach Login/Logout neu laden.
    func refreshServerStatus() async {
        guard let client, let token = auth?.accessToken else {
            serverPlus = false; serverExpiry = nil; publish(); return
        }
        guard let row: JSONObject = try? await client.rpc("my_plus_status", accessToken: token) else { return }
        serverPlus = row.bool("active") ?? false
        serverExpiry = row.string("expires_at").flatMap(Self.parseDate) ?? (serverPlus ? .distantFuture : nil)
        publish()
    }

    /// Löst einen Plus-Code ein. Liefert die Meldung für die Oberfläche.
    func redeem(code: String) async -> (ok: Bool, message: String) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "Bitte gib einen Code ein.") }
        guard let client, let token = auth?.accessToken else { return (false, "Bitte melde dich zuerst an.") }
        isRedeeming = true
        defer { isRedeeming = false }
        do {
            let row: JSONObject = try await client.rpc("redeem_plus_code", parameters: ["p_code": .string(trimmed)], accessToken: token)
            let ok = row.bool("ok") ?? false
            if ok { await refreshServerStatus(); Haptics.confirm() }
            return (ok, row.string("message") ?? (ok ? "Klangradar Plus ist freigeschaltet." : "Der Code hat nicht funktioniert."))
        } catch {
            return (false, "Der Code konnte gerade nicht geprüft werden. Bitte versuch es gleich noch einmal.")
        }
    }

    private func publish() {
        isPlus = storeKitPlus || serverPlus
        expirationDate = isPlus ? [storeKitPlus ? storeKitExpiry : nil, serverPlus ? serverExpiry : nil].compactMap { $0 }.max() : nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case let .verified(transaction) = update { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
            await refreshServerStatus()
        }
    }

    func loadProducts() async {
        guard let loaded = try? await Product.products(for: Self.productIDs) else { return }
        products = loaded.sorted { Self.productIDs.firstIndex(of: $0.id) ?? 0 < Self.productIDs.firstIndex(of: $1.id) ?? 0 }
    }

    func refreshEntitlements() async {
        var active = false
        var expiry: Date?
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration < .now { continue }
            active = true
            expiry = max(expiry ?? .distantPast, transaction.expirationDate ?? .distantFuture)
        }
        storeKitPlus = active
        storeKitExpiry = active ? expiry : nil
        publish()
    }

    /// true bei erfolgreichem Kauf.
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    errorMessage = "Der Kauf konnte nicht bestätigt werden."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                Haptics.confirm()
                return isPlus
            case .pending:
                errorMessage = "Der Kauf wartet noch auf eine Bestätigung (z. B. durch die Familienfreigabe)."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPlus { errorMessage = "Es wurde kein aktives Klangradar-Plus-Abo gefunden." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Wöchentliches Kontingent der Klangradar KI ohne Plus (lokal gezählt).
enum CoachQuota {
    static let weeklyLimit = 5
    private static var key: String {
        let calendar = Calendar(identifier: .iso8601)
        let week = calendar.component(.weekOfYear, from: .now)
        let year = calendar.component(.yearForWeekOfYear, from: .now)
        return "coachQuestions.\(year).\(week)"
    }
    static var used: Int { UserDefaults.standard.integer(forKey: key) }
    static var remaining: Int { max(0, weeklyLimit - used) }
    static func recordQuestion() { UserDefaults.standard.set(used + 1, forKey: key) }
}

enum PlusLimits {
    static let freeLists = 3
}
