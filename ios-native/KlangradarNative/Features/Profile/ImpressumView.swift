import SwiftUI

/// Rechtlich vorgeschriebene Anbieterkennzeichnung (§ 5 DDG) direkt in der
/// App, nicht nur als externer Link auf klangradar.app — Nutzeranfrage
/// "füge das urheberrecht noch in die app ein" bezog sich auf den
/// vollständigen, aktuellen Impressum-Text inklusive Urheberrecht-Abschnitt.
struct ImpressumView: View {
    var body: some View {
        List {
            Section("Angaben gemäß § 5 DDG") {
                Text("Jakob Liess\nGabelsbergerstraße 6\n80333 München\nDeutschland")
            }

            Section("Kontakt") {
                Link("jakob@klangradar.com", destination: URL(string: "mailto:jakob@klangradar.com")!)
            }

            Section("Verantwortlich für den Inhalt") {
                Text("Jakob Liess\nGabelsbergerstraße 6\n80333 München\nDeutschland")
            }

            Section("Haftung für Inhalte") {
                Text("Die Inhalte dieser App wurden mit größtmöglicher Sorgfalt erstellt. Für die Richtigkeit, Vollständigkeit und Aktualität der Inhalte kann jedoch keine Gewähr übernommen werden.")
            }

            Section("Haftung für externe Links") {
                Text("Diese App enthält gegebenenfalls Links zu externen Websites Dritter, auf deren Inhalte kein Einfluss besteht. Für diese fremden Inhalte wird daher keine Gewähr übernommen. Für die Inhalte der verlinkten Seiten ist stets der jeweilige Anbieter oder Betreiber verantwortlich.")
            }

            Section("Urheberrecht") {
                Text("Die durch den Betreiber dieser App erstellten Inhalte und Werke unterliegen dem deutschen Urheberrecht. Inhalte Dritter werden als solche gekennzeichnet. Eine Vervielfältigung, Bearbeitung, Verbreitung oder sonstige Verwertung außerhalb der Grenzen des Urheberrechts bedarf der Zustimmung des jeweiligen Rechteinhabers.")
            }
        }
        .navigationTitle("Impressum")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ImpressumView()
    }
}
