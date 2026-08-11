import SwiftUI

/// Nutzeranfrage: "richte auch in der native app eine fehlermeldung für
/// nutzer ein" — Pendant zu Flutters ReportContentSheet (app/lib/core/
/// widgets/report_content_sheet.dart), gleiche Gründe/DB-Werte, gleiche
/// dezente Platzierung (kein auffälliger Button). Schreibt über
/// UserRepository.reportContent in dieselbe content_reports-Tabelle mit
/// platform="native".
enum ReportReason: String, CaseIterable, Identifiable {
    case wrongImage = "wrong_image"
    case wrongTime = "wrong_time"
    case cancelled = "cancelled"
    case wrongArtist = "wrong_artist"
    case brokenTicketLink = "broken_ticket_link"
    case missingProgram = "missing_program"
    case other = "other"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wrongImage: "Falsches Bild"
        case .wrongTime: "Falsche Uhrzeit"
        case .cancelled: "Veranstaltung abgesagt"
        case .wrongArtist: "Falsche Künstler-/Werkzuordnung"
        case .brokenTicketLink: "Ticketlink defekt"
        case .missingProgram: "Programminformation fehlt"
        case .other: "Sonstiges"
        }
    }

    /// Je Entitätstyp nur die sinnvollen Gründe — deckt sich mit
    /// `_reasonsByEntityType` in der Flutter-App.
    static func allowed(for entityType: String) -> [ReportReason] {
        switch entityType {
        case "event": [.wrongImage, .wrongTime, .cancelled, .wrongArtist, .brokenTicketLink, .missingProgram, .other]
        default: [.wrongImage, .other]
        }
    }
}

/// Dezenter Text-Link (kein auffälliger Button — Melden ist ein
/// Ausnahmefall, keine primäre Aktion). `entityType` muss zu
/// content_reports' entity_type-Check passen ("event"/"venue"/"person"/
/// "ensemble"); für "work" gibt es (wie in Flutter) keinen Melde-Link.
struct ReportContentLink: View {
    let entityType: String
    let entityID: String
    @EnvironmentObject private var reportStore: ReportStore

    @State private var showsSheet = false

    var body: some View {
        Button {
            showsSheet = true
        } label: {
            Text("Fehler melden")
                .font(.system(size: 11))
                .underline()
                .foregroundStyle(.tertiary)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fehler bei diesem Eintrag melden")
        .sheet(isPresented: $showsSheet) {
            ReportContentSheetView(
                entityType: entityType,
                entityID: entityID,
                auth: reportStore.auth,
                userRepository: reportStore.repository
            )
            .presentationDetents([.medium])
        }
    }
}

private struct ReportContentSheetView: View {
    let entityType: String
    let entityID: String
    let auth: AuthStore
    let userRepository: UserRepository?

    @State private var selected: ReportReason?
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var isSubmitted = false
    @Environment(\.dismiss) private var dismiss

    private var reasons: [ReportReason] { ReportReason.allowed(for: entityType) }

    var body: some View {
        NavigationStack {
            Group {
                if isSubmitted {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Danke für deine Meldung", systemImage: "checkmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("Die Redaktion prüft deinen Hinweis.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
                } else {
                    Form {
                        Section("Was stimmt nicht?") {
                            ForEach(reasons) { reason in
                                Button {
                                    selected = reason
                                } label: {
                                    HStack {
                                        Text(reason.label).foregroundStyle(.primary)
                                        Spacer()
                                        if selected == reason {
                                            Image(systemName: "checkmark").foregroundStyle(KlangradarTheme.accent)
                                        }
                                    }
                                }
                            }
                        }
                        Section("Details (optional)") {
                            TextField("Was genau ist falsch?", text: $message, axis: .vertical)
                                .lineLimit(3...5)
                        }
                    }
                }
            }
            .navigationTitle("Fehler melden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSubmitted ? "Fertig" : "Abbrechen") { dismiss() }
                }
                if !isSubmitted {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Button("Senden") { Task { await submit() } }
                                .disabled(selected == nil)
                        }
                    }
                }
            }
        }
    }

    private func submit() async {
        guard let repository = userRepository, let reason = selected, !isSubmitting else { return }
        let token = auth.accessToken ?? ""
        guard !token.isEmpty else { return }
        isSubmitting = true
        do {
            try await repository.reportContent(
                entityType: entityType,
                entityID: entityID,
                reason: reason.rawValue,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : message,
                userID: auth.userID,
                token: token
            )
            isSubmitted = true
        } catch {
            // Fire-and-forget, analog zur Flutter-App: kein Fehler-Toast.
        }
        isSubmitting = false
    }
}
