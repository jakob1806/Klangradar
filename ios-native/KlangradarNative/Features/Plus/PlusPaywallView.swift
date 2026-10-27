import StoreKit
import SwiftUI
import UserNotifications

/// Einstieg für alles rund um Klangradar Plus. Ohne Plus: Angebot mit
/// Funktionen, Paketen, Ablauf der Testphase und Kauf-Button. Nach dem Kauf
/// (oder Code) direkt hier: Willkommen mit "wo finde ich was". Für
/// Plus-Mitglieder: Übersicht mit Status, Funktionen und App-Icon.
/// `feature` hebt die Funktion hervor, von der aus die Seite geöffnet wurde.
/// Neu gestaltet von Claude Code (Nutzerwunsch 27.10.2026).
struct PlusPaywallView: View {
    var feature: PlusFeature?
    var reason: String?
    @ObservedObject private var store = PlusStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = "de.klangradar.plus.yearly"
    @State private var activatedHere = false
    @State private var code = ""
    @State private var codeResult: (ok: Bool, message: String)?
    @State private var showsCodeField = false
    @State private var isLoadingProducts = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    if store.isPlus {
                        if activatedHere { PlusWelcomeContent { dismiss() } } else { PlusMemberContent() }
                    } else {
                        hero
                        featureList
                        plans
                        trialTimeline
                        faq
                        codeSection
                        legal
                    }
                }
                .padding(.horizontal, KlangradarTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background { KlangradarBackground().ignoresSafeArea() }
            .safeAreaInset(edge: .bottom) { if !store.isPlus { purchaseBar } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schließen", systemImage: "xmark") { dismiss() }
                }
            }
            .task {
                if store.products.isEmpty { await store.loadProducts() }
                isLoadingProducts = false
            }
            .alert("Klangradar Plus", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(store.errorMessage ?? "") }
            .animation(.snappy, value: store.isPlus)
        }
    }

    // MARK: Angebot

    private var selectedProduct: Product? {
        store.products.first { $0.id == selectedID } ?? store.products.first
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach([PlusFeature.instantAlerts, .coach, .concertYear, .appIcons]) { item in
                    Image(systemName: item.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.16), in: .circle)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Klangradar Plus").font(.system(size: 36, weight: .bold, design: .serif))
                Text("Mehr aus jedem Konzertabend.").font(.title3).opacity(0.85)
            }
            if let text = reason ?? feature?.paywallReason {
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(.white.opacity(0.16), in: .rect(cornerRadius: 12, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PlusStyle.gradient, in: .rect(cornerRadius: 28, style: .continuous))
    }

    private var orderedFeatures: [PlusFeature] {
        guard let feature else { return PlusFeature.allCases }
        return [feature] + PlusFeature.allCases.filter { $0 != feature }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Das bekommst du").font(.title3.bold())
            ForEach(orderedFeatures) { item in
                PlusFeatureRow(feature: item, highlighted: item == feature, showsLocation: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var plans: some View {
        if store.products.isEmpty {
            VStack(spacing: 8) {
                if isLoadingProducts {
                    ProgressView()
                    Text("Pakete werden geladen …").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Die Abos sind gerade nicht erreichbar.").font(.subheadline.weight(.semibold))
                    Text("Hast du einen Code, kannst du ihn unten einlösen.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Wähle dein Paket").font(.title3.bold())
                HStack(alignment: .top, spacing: 12) {
                    ForEach(store.products, id: \.id) { product in planCard(product) }
                }
            }
        }
    }

    private func isYearly(_ product: Product) -> Bool {
        product.subscription?.subscriptionPeriod.unit == .year
    }

    private var savingsPercent: Int? {
        guard let yearly = store.products.first(where: isYearly),
              let monthly = store.products.first(where: { !isYearly($0) }), monthly.price > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: yearly.price / (monthly.price * 12)).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded())
        return percent > 0 ? percent : nil
    }

    private func planCard(_ product: Product) -> some View {
        let selected = selectedProduct?.id == product.id
        let yearly = isYearly(product)
        return Button {
            Haptics.light()
            withAnimation(.snappy) { selectedID = product.id }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(yearly ? "Jährlich" : "Monatlich").font(.headline)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? KlangradarTheme.accent : .secondary)
                }
                Text(product.displayPrice).font(.title2.bold().monospacedDigit())
                Text(yearly ? "pro Jahr" : "pro Monat").font(.caption).foregroundStyle(.secondary)
                if yearly {
                    Text("nur \((product.price / 12).formatted(product.priceFormatStyle)) im Monat")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(KlangradarTheme.accent)
                } else {
                    Text("flexibel kündbar").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? KlangradarTheme.accent : Color.primary.opacity(0.08), lineWidth: selected ? 2.5 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if yearly, let savingsPercent {
                    Text("−\(savingsPercent) %")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(PlusStyle.gradient, in: .capsule)
                        .offset(x: -10, y: -11)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var hasTrial: Bool { selectedProduct?.subscription?.introductoryOffer?.paymentMode == .freeTrial }
    private var trialDays: Int {
        guard let period = selectedProduct?.subscription?.introductoryOffer?.period else { return 7 }
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        default: return 7
        }
    }

    private func periodText(_ product: Product) -> String { isYearly(product) ? "im Jahr" : "im Monat" }

    @ViewBuilder private var trialTimeline: some View {
        if hasTrial, let product = selectedProduct {
            VStack(alignment: .leading, spacing: 0) {
                Text("So läuft die Testphase").font(.title3.bold()).padding(.bottom, 14)
                timelineStep("lock.open.fill", "Heute", "Alles freigeschaltet. Du zahlst nichts.", isLast: false)
                timelineStep("bell.fill", "Tag \(max(1, trialDays - 2))", "Wir erinnern dich per Mitteilung, dass die Testphase bald endet.", isLast: false)
                timelineStep("star.fill", "Tag \(trialDays)", "Plus startet für \(product.displayPrice) \(periodText(product)). Vorher jederzeit kündbar.", isLast: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }

    private func timelineStep(_ symbol: String, _ title: String, _ text: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(KlangradarTheme.accent, in: .circle)
                if !isLast {
                    Rectangle().fill(KlangradarTheme.accent.opacity(0.3)).frame(width: 2).frame(minHeight: 26)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
    }

    private var faq: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Gut zu wissen").font(.title3.bold()).padding(.bottom, 8)
            faqItem("Wie kündige ich?", "In den Einstellungen deines iPhones unter deinem Namen → Abonnements, oder hier in der App unter Klangradar Plus → Abo verwalten. Plus läuft dann bis zum Ende des bezahlten Zeitraums.")
            faqItem("Was bleibt kostenlos?", "Alles, was du heute nutzt: Konzerte finden, Karte, Kalender, Merkliste, Folgen, Tagebuch und Mitteilungen. Plus kommt obendrauf.")
            faqItem("Gilt Plus auf allen Geräten?", "Ja, auf allen Geräten mit deiner Apple-ID. Ein eingelöster Code gilt für dein Klangradar-Konto.")
        }
    }

    private func faqItem(_ question: String, _ answer: String) -> some View {
        DisclosureGroup {
            Text(answer).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        } label: {
            Text(question).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
        }
        .padding(.vertical, 10)
        .tint(.secondary)
    }

    private var purchaseBar: some View {
        VStack(spacing: 8) {
            Button { Task { await purchase() } } label: {
                ZStack {
                    if store.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        VStack(spacing: 1) {
                            Text(purchaseTitle).font(.headline)
                            if let product = selectedProduct, hasTrial {
                                Text("danach \(product.displayPrice) \(periodText(product))").font(.caption).opacity(0.85)
                            }
                        }
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(PlusStyle.gradient, in: .capsule)
                .shadow(color: KlangradarTheme.accent.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(store.isPurchasing || selectedProduct == nil)
            .opacity(selectedProduct == nil ? 0.5 : 1)
            Text(selectedProduct == nil ? "Mit Code freischalten: unten auf der Seite." : "Verlängert sich automatisch · jederzeit kündbar")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, KlangradarTheme.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var purchaseTitle: String {
        guard let product = selectedProduct else { return "Plus gerade nicht verfügbar" }
        if hasTrial { return "\(trialDays) Tage kostenlos testen" }
        return "Plus für \(product.displayPrice) \(periodText(product))"
    }

    private func purchase() async {
        guard let product = selectedProduct else { return }
        let withTrial = hasTrial
        let days = trialDays
        if await store.purchase(product) {
            if withTrial {
                if (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) == true {
                    PlusTrialReminder.schedule(trialDays: days, price: "\(product.displayPrice) \(periodText(product))")
                }
            }
            activatedHere = true
        }
    }

    // MARK: Code und Rechtliches

    @ViewBuilder private var codeSection: some View {
        if showsCodeField || (store.products.isEmpty && !isLoadingProducts) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Code einlösen").font(.headline)
                HStack(spacing: 10) {
                    TextField("Code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(.thinMaterial, in: .rect(cornerRadius: 14))
                        .submitLabel(.go)
                        .onSubmit(redeem)
                    Button(action: redeem) {
                        if store.isRedeeming { ProgressView() } else { Text("Einlösen").font(.headline) }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(store.isRedeeming || code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let codeResult {
                    Label(codeResult.message, systemImage: codeResult.ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(codeResult.ok ? Color.green : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button("Ich habe einen Code") { withAnimation { showsCodeField = true } }
                .font(.subheadline.weight(.medium))
        }
    }

    private func redeem() {
        Task {
            let result = await store.redeem(code: code)
            codeResult = result
            if result.ok { activatedHere = true }
        }
    }

    private var legal: some View {
        HStack(spacing: 16) {
            Button("Käufe wiederherstellen") { Task { await store.restore() } }
            Link("Nutzungsbedingungen", destination: URL(string: "https://klangradar.com/nutzungsbedingungen")!)
            Link("Datenschutz", destination: URL(string: "https://klangradar.com/datenschutz")!)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }
}

/// Eine Plus-Funktion mit Symbol, Nutzen und optional dem Ort in der App.
struct PlusFeatureRow: View {
    let feature: PlusFeature
    var highlighted = false
    var showsLocation = true

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(feature.color.gradient, in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title).font(.headline)
                Text(feature.pitch).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if showsLocation {
                    Label(feature.whereToFind, systemImage: "location.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(KlangradarTheme.accent)
                        .padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(highlighted ? 12 : 0)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(feature.color.opacity(0.1))
            }
        }
    }
}

/// Direkt nach Kauf oder Code: was jetzt frei ist und wo es liegt.
private struct PlusWelcomeContent: View {
    let onDone: () -> Void
    @State private var notificationsAllowed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(PlusStyle.gradient)
                Text("Willkommen bei Plus").font(.system(size: 34, weight: .bold, design: .serif))
                Text("Alles ist freigeschaltet. Hier findest du deine neuen Funktionen.")
                    .font(.title3).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !notificationsAllowed {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Damit „Neue Termine sofort“ ankommt, braucht Klangradar Mitteilungen.")
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Mitteilungen erlauben") {
                        Task {
                            notificationsAllowed = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                            if notificationsAllowed { UIApplication.shared.registerForRemoteNotifications() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
                .padding(16)
                .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 18, style: .continuous))
            }
            ForEach(PlusFeature.allCases) { item in
                PlusFeatureRow(feature: item)
            }
            AppIconPicker()
            Button(action: onDone) {
                Text("Los geht’s").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(PlusStyle.gradient, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
    }
}

/// Für Plus-Mitglieder: Status, Funktionen mit Ort, App-Icon, Abo verwalten.
private struct PlusMemberContent: View {
    @ObservedObject private var store = PlusStore.shared
    @State private var showsManage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Plus ist aktiv", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.bold))
                Text("Danke, dass du dabei bist.").font(.system(size: 30, weight: .bold, design: .serif))
                Text(statusText).font(.subheadline).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PlusStyle.gradient, in: .rect(cornerRadius: 28, style: .continuous))

            Text("Deine Plus-Funktionen").font(.title3.bold())
            ForEach(PlusFeature.allCases) { item in
                PlusFeatureRow(feature: item)
            }
            AppIconPicker()
            if store.hasStoreKitSubscription {
                Button("Abo verwalten") { showsManage = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .manageSubscriptionsSheet(isPresented: $showsManage)
            }
        }
    }

    private var statusText: String {
        if let expiry = store.expirationDate, expiry < .distantFuture {
            return (store.hasStoreKitSubscription ? "Verlängert sich am " : "Gültig bis ") + expiry.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_DE")))
        }
        return store.hasStoreKitSubscription ? "Dein Abo läuft." : "Freigeschaltet per Code, ohne Ablaufdatum."
    }
}

/// Auswahl des App-Icons (Plus).
struct AppIconPicker: View {
    @State private var current = AppIconChoice.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App-Icon").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Button {
                            Haptics.light()
                            current = choice
                            Task { await choice.apply() }
                        } label: {
                            VStack(spacing: 6) {
                                Image(choice.previewImage)
                                    .resizable()
                                    .frame(width: 62, height: 62)
                                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(current == choice ? KlangradarTheme.accent : Color.primary.opacity(0.1), lineWidth: current == choice ? 3 : 1)
                                    }
                                Text(choice.label).font(.caption).foregroundStyle(current == choice ? .primary : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear { current = AppIconChoice.current }
    }
}
