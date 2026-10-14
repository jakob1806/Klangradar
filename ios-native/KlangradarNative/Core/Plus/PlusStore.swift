import Foundation
import StoreKit

/// Klangradar Plus über Apples In-App-Kauf (StoreKit 2). Die Freischaltung
/// wird lokal aus den von Apple signierten Transaktionen abgeleitet
/// (`Transaction.currentEntitlements`); ein Server-Abgleich folgt in einem
/// zweiten Schritt (siehe docs/15-preise-und-klangradar-plus.md).
@MainActor
final class PlusStore: ObservableObject {
    static let shared = PlusStore()
    static let productIDs = ["de.klangradar.plus.yearly", "de.klangradar.plus.monthly"]

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPlus = false
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isPurchasing = false
    @Published var errorMessage: String?

    /// Limits greifen nur, wenn Plus tatsächlich kaufbar ist — sonst würde
    /// man Nutzer ohne Ausweg blockieren (z. B. vor Freischaltung in App Store Connect).
    var isOfferAvailable: Bool { !products.isEmpty }
    var enforcesLimits: Bool { isOfferAvailable && !isPlus }

    private var updatesTask: Task<Void, Never>?

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
        isPlus = active
        expirationDate = active ? expiry : nil
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
