import SwiftUI

/// Aus ProfileView.swift extrahiert — siehe Kommentar in InterestsView.swift,
/// gleicher Grund: wird jetzt auch als Onboarding-Schritt eingebettet.
struct NotificationSettingsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    /// Nur im Onboarding-Schritt gesetzt (siehe NotificationsStepView) — als
    /// Form-Section statt als fixer VStack-Sibling davor, damit der Titel
    /// zuverlässig unterhalb des Fortschritts-Headers bleibt (derselbe
    /// Grund wie bei FollowCategoryStepView: ein reiner VStack vor einem
    /// scrollbaren Container respektiert das per NavigationStack gesetzte
    /// safeAreaInset(top) nicht zuverlässig).
    var introTitle: String? = nil
    var introSubtitle: String? = nil
    @State private var preferences = NotificationPreferences()
    @State private var newsletter = false
    @State private var showsPlusPaywall = false

    var body: some View {
        Form {
            if let introTitle {
                Section {
                    VStack(spacing: 6) {
                        Text(introTitle).font(.title2.bold())
                        if let introSubtitle {
                            Text(introSubtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
            }
            // Neu geordnet nach dem Mitteilungs-Konzept (Claude Code, 01.11.2026):
            // Wichtiges sofort, Planung genau eine pro Konzert, alles andere
            // in einem selbst gewählten Wochenbudget.
            Section {
                Label("Absagen und Verschiebungen kommen immer sofort", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Toggle("Zeit- und Terminänderungen", isOn: binding(\.changes, "push_changes"))
            } header: {
                Text("Wichtig")
            } footer: {
                Text("Für Konzerte, die du gemerkt, geplant oder im Abo hast.")
            }

            Section {
                Toggle("Erinnerung am Konzerttag", isOn: binding(\.reminderDayBefore, "reminder_day_before"))
                Toggle("Fast ausverkauft", isOn: binding(\.almostSoldOut, "almost_sold_out"))
                Toggle("„Wie war's?“ am Tag danach", isOn: binding(\.howWasIt, "push_how_was_it"))
            } header: {
                Text("Deine Konzerte")
            } footer: {
                Text("Genau eine Erinnerung pro Konzert – auch für Abo-Konzerte.")
            }

            Section {
                Picker("Neue Konzerte von Gefolgten", selection: choice(\.newFollowed, "push_new_followed")) {
                    Text("Aus").tag("off")
                    Text("Einmal pro Woche").tag("weekly")
                    Text("Täglich gesammelt").tag("daily")
                    Text(PlusStore.shared.isPlus ? "Zweimal täglich" : "Zweimal täglich (Plus)").tag("twice_daily")
                }
                Toggle("Tipp der Woche (donnerstags)", isOn: binding(\.weeklyPick, "push_weekly_pick"))
            } header: {
                Text("Entdecken")
            } footer: {
                if PlusStore.shared.isPlus || preferences.newFollowed != "twice_daily" {
                    Text("Neue Termine kommen immer gesammelt in einer Mitteilung. Ob du für einzelne Künstler:innen, Ensembles oder Orte benachrichtigt wirst, stellst du auf deren Seite mit der Glocke ein.")
                } else {
                    Button { showsPlusPaywall = true } label: {
                        Text("Zweimal täglich gibt es mit ") + Text("Klangradar Plus").foregroundStyle(KlangradarTheme.accent).bold() + Text(". Bis dahin kommt die Sammlung einmal täglich.")
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Picker("Anfragen & Einladungen", selection: choice(\.friends, "push_friends")) {
                    Text("Sofort").tag("direct")
                    Text("Einmal täglich").tag("daily")
                    Text("Aus").tag("off")
                }
                Toggle("Applaus, Kommentare, wer mitgeht", isOn: binding(\.friendActivity, "push_friend_activity"))
            } header: {
                Text("Freunde")
            } footer: {
                Text("Aktivitäten deiner Freunde kommen – wenn eingeschaltet – gesammelt einmal am Tag. In der App siehst du sie immer.")
            }

            Section {
                Picker("Höchstens pro Woche", selection: limitBinding) {
                    ForEach([5, 10, 15, 20, 30], id: \.self) { Text("\($0) Mitteilungen").tag($0) }
                }
            } header: {
                Text("Wie viel?")
            } footer: {
                Text("Gilt für Entdecken und Freunde. Wichtiges und Erinnerungen an deine Konzerte zählen nicht mit. Zwischen 21 und 8 Uhr ist Ruhe.")
            }

            if auth.userID != nil {
                Section {
                    Toggle("Deine Konzertwoche", isOn: binding(\.emailWeeklyDigest, "email_weekly_digest"))
                    Toggle("Neue Termine gefolgter Personen, Ensembles & Orte", isOn: binding(\.emailFollowedNewEvent, "email_followed_new_event"))
                    Toggle("Absagen & Änderungen gemerkter Konzerte", isOn: binding(\.emailEventChanges, "email_event_changes"))
                    Toggle("Erinnerung am Vortag", isOn: binding(\.emailReminderDayBefore, "email_reminder_day_before"))
                } header: {
                    Text("E-Mail")
                } footer: {
                    Text("„Deine Konzertwoche“ kommt jeden Donnerstag: persönlich ausgewählte Konzerte der nächsten Tage in deiner Stadt, nach deinen gefolgten Künstler:innen, Ensembles und Orten, deiner Merkliste, deinen Lieblingsgenres und dem, was deine Freunde vorhaben. Jede E-Mail enthält einen Link zum Abmelden.")
                }

                Section {
                    Toggle("Klangradar-Newsletter", isOn: newsletterBinding)
                } footer: {
                    Text("Neuigkeiten, Saison-Highlights und Empfehlungen der Redaktion, etwa einmal im Monat. Du kannst die Einwilligung jederzeit hier widerrufen.")
                }
            }
        }
        .navigationTitle("Benachrichtigungen")
        .sheet(isPresented: $showsPlusPaywall) { PlusPaywallView(feature: .instantAlerts) }
        .task {
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            preferences = (try? await repository.preferences(userID: id, token: token)) ?? NotificationPreferences()
            newsletter = (try? await repository.newsletterOptIn(userID: id, token: token)) ?? false
        }
    }

    private func choice(_ keyPath: WritableKeyPath<NotificationPreferences, String>, _ column: String) -> Binding<String> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in
            if column == "push_new_followed", value == "twice_daily", !PlusStore.shared.isPlus {
                showsPlusPaywall = true
                return
            }
            preferences[keyPath: keyPath] = value
            Haptics.light()
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            Task { try? await repository.setPreferenceValue(userID: id, token: token, column: column, value: .string(value)) }
        })
    }

    private var limitBinding: Binding<Int> {
        Binding(get: { preferences.weeklyLimit }, set: { value in
            preferences.weeklyLimit = value
            Haptics.light()
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            Task { try? await repository.setPreferenceValue(userID: id, token: token, column: "push_weekly_limit", value: .number(Double(value))) }
        })
    }

    private var newsletterBinding: Binding<Bool> {
        Binding(get: { newsletter }, set: { value in
            newsletter = value
            Haptics.light()
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            Task { try? await repository.setNewsletterOptIn(value, userID: id, token: token) }
        })
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>, _ column: String) -> Binding<Bool> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in
            preferences[keyPath: keyPath] = value
            // Generated by Claude Code — "Erinnerung am Vortag" ist die
            // eigentliche Termin-Erinnerung: beim Aktivieren ein Erfolgs-
            // Impuls ("sobald die Erinnerung gesetzt wurde"), sonst nur ein
            // leichter Tick wie bei jedem anderen Einstellungs-Toggle.
            if column == "reminder_day_before", value {
                Haptics.confirm()
            } else {
                Haptics.light()
            }
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            Task { try? await repository.setPreference(userID: id, token: token, column: column, value: value) }
        })
    }
}
