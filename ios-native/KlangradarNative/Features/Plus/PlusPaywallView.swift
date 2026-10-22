import StoreKit
import SwiftUI

/// Bezahl-Bildschirm für Klangradar Plus. `reason` erklärt, warum er gerade
/// erscheint (z. B. KI-Kontingent erreicht).
struct PlusPaywallView: View {
    var reason: String?
    @ObservedObject private var store = PlusStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = PlusStore.productIDs[0]

    private let benefits: [(icon: String, title: String, detail: String)] = [
        ("sparkles", "Klangradar KI ohne Limit", "Frag so viel du willst – Programme, Abendplanung, Empfehlungen."),
        ("bell.badge", "Vorverkaufs-Alarm sofort", "Neue Termine deiner Künstler und Ensembles in Echtzeit."),
        ("list.bullet.rectangle", "Unbegrenzte Listen", "Sammle Konzerte für jede Saison und jeden Anlass."),
        ("chart.bar.xaxis", "Konzerttagebuch", "Jahresrückblick und Statistiken zu deinen Konzertbesuchen."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if let reason {
                        Text(reason)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    if store.isPlus { activeCard } else { benefitsCard; plans; purchaseButton; legal }
                }
                .padding(KlangradarTheme.pagePadding)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background { KlangradarBackground().ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen", systemImage: "xmark") { dismiss() }
                }
            }
            .task { if store.products.isEmpty { await store.loadProducts() } }
            .alert("Klangradar Plus", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(store.errorMessage ?? "") }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(KlangradarTheme.accent)
            Text("Klangradar Plus").font(.largeTitle.bold())
            Text("Mehr aus jedem Konzertabend.").font(.headline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var benefitsCard: some View {
        LiquidGlassSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(benefits, id: \.title) { benefit in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: benefit.icon)
                            .font(.title3)
                            .foregroundStyle(KlangradarTheme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(benefit.title).font(.headline)
                            Text(benefit.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var plans: some View {
        if store.products.isEmpty {
            Text("Klangradar Plus ist in Kürze verfügbar.")
                .font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 12) {
                ForEach(store.products, id: \.id) { product in
                    planCard(product)
                }
            }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isSelected = selectedID == product.id
        let isYearly = product.subscription?.subscriptionPeriod.unit == .year
        return Button {
            Haptics.light()
            selectedID = product.id
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? KlangradarTheme.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "Jährlich" : "Monatlich").font(.headline)
                        if isYearly {
                            Text("Beliebt")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(KlangradarTheme.accent.opacity(0.15), in: .capsule)
                                .foregroundStyle(KlangradarTheme.accent)
                        }
                    }
                    if isYearly, let monthly = monthlyEquivalent(product) {
                        Text("entspricht \(monthly) pro Monat").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(product.displayPrice).font(.headline.monospacedDigit())
            }
            .padding(16)
            .background(.thinMaterial, in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isSelected ? KlangradarTheme.accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var purchaseButton: some View {
        if let product = store.products.first(where: { $0.id == selectedID }) ?? store.products.first {
            let hasTrial = product.subscription?.introductoryOffer?.paymentMode == .freeTrial
            Button {
                Task { if await store.purchase(product) { dismiss() } }
            } label: {
                Group {
                    if store.isPurchasing { ProgressView().tint(.white) }
                    else { Text(hasTrial ? "7 Tage kostenlos testen" : "Weiter") }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(.capsule)
            .disabled(store.isPurchasing)
            Text(hasTrial
                 ? "Danach \(product.displayPrice) \(periodLabel(product)). Verlängert sich automatisch, jederzeit in den Einstellungen kündbar."
                 : "\(product.displayPrice) \(periodLabel(product)). Verlängert sich automatisch, jederzeit in den Einstellungen kündbar.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var legal: some View {
        HStack(spacing: 16) {
            Button("Käufe wiederherstellen") { Task { await store.restore() } }
            Link("Nutzungsbedingungen", destination: URL(string: "https://klangradar.com/nutzungsbedingungen")!)
            Link("Datenschutz", destination: URL(string: "https://klangradar.com/datenschutz")!)
        }
        .font(.caption)
        .padding(.bottom, 12)
    }

    private var activeCard: some View {
        LiquidGlassSurface(cornerRadius: 24) {
            VStack(spacing: 10) {
                Label("Plus ist aktiv", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(KlangradarTheme.accent)
                if let expiry = store.expirationDate, expiry < .distantFuture {
                    Text("Verlängert sich am \(expiry.formatted(date: .long, time: .omitted))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ManageSubscriptionButton()
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
    }

    private func periodLabel(_ product: Product) -> String {
        product.subscription?.subscriptionPeriod.unit == .year ? "pro Jahr" : "pro Monat"
    }

    private func monthlyEquivalent(_ product: Product) -> String? {
        (product.price / 12).formatted(product.priceFormatStyle) as String?
    }
}

private struct ManageSubscriptionButton: View {
    @State private var showsManage = false
    var body: some View {
        Button("Abo verwalten") { showsManage = true }
            .manageSubscriptionsSheet(isPresented: $showsManage)
    }
}
