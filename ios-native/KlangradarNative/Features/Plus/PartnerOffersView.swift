import SwiftUI

/// Plus-Vorteile bei Partnern (partner_offers). Beschreibung für alle,
/// Gutscheincode nur mit aktivem Plus.
struct PartnerOffersView: View {
    @ObservedObject private var partners = PartnerStore.shared
    @ObservedObject private var plus = PlusStore.shared
    @State private var showsPaywall = false
    @State private var copiedID: UUID?

    var body: some View {
        List {
            if partners.offers.isEmpty {
                ContentUnavailableView(
                    "Bald mehr Vorteile",
                    systemImage: "gift",
                    description: Text("Wir sprechen gerade mit Konzerthäusern, Cafés und Musikläden. Neue Vorteile erscheinen hier automatisch.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(partners.offers) { offer in
                VStack(alignment: .leading, spacing: 8) {
                    Text(offer.partnerName.uppercased()).font(.caption.bold()).tracking(1).foregroundStyle(KlangradarTheme.accent)
                    Text(offer.title).font(.headline)
                    if let description = offer.description { Text(description).font(.subheadline).foregroundStyle(.secondary) }
                    if let validUntil = offer.validUntil {
                        Text("Gültig bis \(KlangradarDateTime.string(validUntil, format: "d. MMMM yyyy"))").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        if let code = offer.code, !code.isEmpty {
                            if plus.isPlus {
                                Button {
                                    UIPasteboard.general.string = code
                                    Haptics.confirm()
                                    copiedID = offer.id
                                } label: {
                                    Label(copiedID == offer.id ? "Kopiert" : code, systemImage: copiedID == offer.id ? "checkmark" : "doc.on.doc")
                                        .font(.subheadline.monospaced().weight(.semibold))
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("Code mit Plus freischalten", systemImage: "lock.fill") { showsPaywall = true }
                                    .buttonStyle(.borderedProminent)
                                    .tint(KlangradarTheme.accent)
                            }
                        }
                        Spacer()
                        if let url = offer.url { Link("Zum Partner", destination: url).font(.subheadline) }
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Partner-Vorteile")
        .refreshable { await partners.load() }
        .sheet(isPresented: $showsPaywall) {
            PlusPaywallView(reason: "Mit Plus erhältst du die Gutscheincodes unserer Partner.")
        }
    }
}
