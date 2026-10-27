import SwiftUI

private func statusLabel(_ status: String) -> (text: String, symbol: String, color: Color) {
    switch status {
    case "going": ("Dabei", "checkmark.circle.fill", .green)
    case "maybe": ("Vielleicht", "questionmark.circle.fill", .orange)
    case "declined": ("Abgesagt", "xmark.circle.fill", .secondary)
    default: ("Eingeladen", "envelope.fill", KlangradarTheme.accent)
    }
}

/// Karte in der Pläne-Liste.
struct PlanCard: View {
    let plan: ConcertPlan

    var body: some View {
        NavigationLink { PlanDetailView(planID: plan.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    CachedAsyncImage(url: plan.event.imageURL, maxPixel: 240) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Color.secondary.opacity(0.12).overlay { Image(systemName: "music.note") } }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plan.event.title).font(.headline).lineLimit(2)
                        Text(plan.event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if plan.hasMeeting {
                            Label(meetingLine, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(KlangradarTheme.accent).lineLimit(1)
                        }
                    }
                }
                HStack {
                    AvatarStack(people: plan.going.map(\.person), size: 24)
                    Text(plan.going.isEmpty ? "Noch keine Zusagen" : "\(plan.going.count) dabei").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    let status = statusLabel(plan.myStatus)
                    Label(status.text, systemImage: status.symbol).font(.caption.weight(.semibold)).foregroundStyle(status.color)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var meetingLine: String {
        [plan.meetingTime.map { "\(KlangradarDateTime.string($0, format: "HH:mm")) Uhr" }, plan.meetingPoint].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Plan anlegen: Freunde wählen, optional Treffpunkt/Uhrzeit, Nachricht.
/// `quickAsk` = "Wer kommt mit?" ohne Treffpunkt-Felder.
struct PlanComposerView: View {
    let event: ConcertEvent
    var quickAsk = false
    var onCreated: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []
    @State private var withMeeting = false
    @State private var meetingPoint = ""
    @State private var meetingTime = Date()
    @State private var note = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    /// Punkt 9: weitere gemerkte Konzerte zur Abstimmung stellen (max. 2).
    @State private var alternatives: [ConcertEvent] = []
    @State private var pollSelection: Set<UUID> = []

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    EventArtwork(event: event)
                        .frame(width: 60, height: 60)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title).font(.headline).lineLimit(2)
                        Text(event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }

            Section {
                FriendPicker(selection: $selection)
            } header: {
                Text("Wen möchtest du mitnehmen?")
            } footer: {
                Text("Wer zusagt, bekommt das Konzert automatisch als „Ich gehe hin“ gemerkt.")
            }

            if !quickAsk && !alternatives.isEmpty {
                Section {
                    ForEach(alternatives.prefix(8)) { option in
                        Button {
                            if pollSelection.contains(option.id) { pollSelection.remove(option.id) }
                            else if pollSelection.count < 2 { pollSelection.insert(option.id) }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                    Text(option.startDate.map { KlangradarDateTime.string($0, format: "EE d. MMM, HH:mm") } ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: pollSelection.contains(option.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(pollSelection.contains(option.id) ? KlangradarTheme.accent : Color.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Zur Wahl stellen (optional)")
                } footer: {
                    Text(pollSelection.isEmpty ? "Bis zu zwei weitere gemerkte Konzerte – deine Freunde stimmen ab, das mit den meisten Stimmen wird euer Abend." : "Abstimmung mit \(pollSelection.count + 1) Konzerten.")
                }
            }

            if !quickAsk && pollSelection.isEmpty {
                Section {
                    Toggle("Treffpunkt vereinbaren", isOn: $withMeeting.animation())
                    if withMeeting {
                        TextField("Wo? z. B. Foyer, linker Eingang", text: $meetingPoint)
                        DatePicker("Um", selection: $meetingTime, displayedComponents: [.hourAndMinute])
                    }
                }
            }

            Section("Nachricht (optional)") {
                TextField(quickAsk ? "Hast du Lust mitzukommen?" : "z. B. Danach noch etwas essen?", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle(quickAsk ? "Wer kommt mit?" : "Konzertabend planen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSending ? "Senden …" : "Einladen") { Task { await send() } }
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty || isSending)
            }
        }
        .onAppear {
            // Standard-Treffpunkt: 30 Minuten vor Beginn.
            if let start = event.startDate { meetingTime = start.addingTimeInterval(-30 * 60) }
        }
        .task {
            guard !quickAsk, let repository = SocialStore.shared.repository, let token = SocialStore.shared.token,
                  let userID = SocialStore.shared.auth?.userID else { return }
            alternatives = ((try? await repository.favoriteEvents(userID: userID, token: token)) ?? [])
                .filter { $0.id != event.id && ($0.startDate ?? .distantPast) > Date() }
                .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        }
    }

    private func send() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        isSending = true
        defer { isSending = false }
        do {
            if !pollSelection.isEmpty {
                try await repository.createPlanPoll(eventIDs: [event.id] + Array(pollSelection), friendIDs: Array(selection), note: note.isEmpty ? nil : note, token: token)
                Haptics.confirm()
                await SocialStore.shared.refresh()
                onCreated?()
                dismiss()
                return
            }
            try await repository.createConcertPlan(
                eventID: event.id,
                friendIDs: Array(selection),
                meetingPoint: withMeeting ? meetingPoint : nil,
                meetingTime: withMeeting ? meetingTime : nil,
                note: note.isEmpty ? nil : note,
                token: token
            )
            Haptics.confirm()
            await SocialStore.shared.refresh()
            onCreated?()
            dismiss()
        } catch {
            errorMessage = "Die Einladung konnte nicht gesendet werden. Bitte versuche es erneut."
        }
    }
}

/// Plan-Detail: Konzert, Treffpunkt, Teilnehmende, eigene Antwort.
struct PlanDetailView: View {
    let planID: UUID
    var onChange: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var plan: ConcertPlan?
    @State private var isLoading = true
    @State private var showsInvite = false
    @State private var inviteSelection: Set<UUID> = []
    @State private var showsEdit = false
    @State private var confirmsLeave = false
    @State private var poll: [PlanPollOption] = []

    var body: some View {
        Group {
            if let plan {
                List {
                    if poll.isEmpty {
                        Section { SocialEventRow(event: plan.event) }
                    } else {
                        Section {
                            PlanPollSection(options: poll, isOwner: plan.isOwner) { option in
                                await vote(option)
                            } onDecide: {
                                await decide()
                            }
                        } header: {
                            Text("Abstimmung")
                        } footer: {
                            Text("Sobald alle abgestimmt haben, steht euer Konzert fest.")
                        }
                    }

                    if plan.hasMeeting || plan.note != nil {
                        Section("Treffpunkt") {
                            if let time = plan.meetingTime {
                                Label("\(KlangradarDateTime.string(time, format: "EEEE, HH:mm")) Uhr", systemImage: "clock")
                            }
                            if let point = plan.meetingPoint { Label(point, systemImage: "mappin.and.ellipse") }
                            if let note = plan.note { Label(note, systemImage: "text.bubble") }
                        }
                    }

                    Section("Deine Antwort") {
                        HStack(spacing: 8) {
                            responseButton("Dabei", status: "going", symbol: "checkmark", plan: plan)
                            responseButton("Vielleicht", status: "maybe", symbol: "questionmark", plan: plan)
                            responseButton("Kann nicht", status: "declined", symbol: "xmark", plan: plan)
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    }

                    Section("Wer kommt mit (\(plan.going.count))") {
                        ForEach(plan.members) { member in
                            HStack(spacing: 12) {
                                SocialAvatar(name: member.person.name, url: member.person.avatarURL, size: 36)
                                Text(member.person.name)
                                Spacer()
                                let status = statusLabel(member.status)
                                Label(status.text, systemImage: status.symbol).font(.caption.weight(.semibold)).foregroundStyle(status.color)
                            }
                        }
                        Button("Weitere Freunde einladen", systemImage: "person.badge.plus") { showsInvite = true }
                    }

                    Section {
                        if plan.isOwner {
                            Button("Treffpunkt bearbeiten", systemImage: "pencil") { showsEdit = true }
                        }
                        Button(plan.isOwner ? "Plan löschen" : "Plan verlassen", systemImage: plan.isOwner ? "trash" : "rectangle.portrait.and.arrow.right", role: .destructive) {
                            confirmsLeave = true
                        }
                    }
                }
                .confirmationDialog(plan.isOwner ? "Plan für alle löschen?" : "Plan verlassen?", isPresented: $confirmsLeave, titleVisibility: .visible) {
                    Button(plan.isOwner ? "Löschen" : "Verlassen", role: .destructive) { Task { await leave() } }
                }
                .sheet(isPresented: $showsInvite) {
                    NavigationStack {
                        List { FriendPicker(selection: $inviteSelection, excluded: Set(plan.members.map(\.id))) }
                            .navigationTitle("Freunde einladen")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { showsInvite = false } }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Einladen") { Task { await invite() } }.disabled(inviteSelection.isEmpty)
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showsEdit) {
                    NavigationStack { PlanMeetingEditor(plan: plan) { await load() } }
                        .presentationDetents([.medium])
                }
            } else if isLoading {
                ProgressView()
            } else {
                ContentUnavailableView("Plan nicht gefunden", systemImage: "calendar.badge.exclamationmark", description: Text("Der Plan wurde gelöscht oder du bist nicht mehr dabei."))
            }
        }
        .navigationTitle("Konzertabend")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func responseButton(_ title: String, status: String, symbol: String, plan: ConcertPlan) -> some View {
        let selected = plan.myStatus == status
        return Button {
            Task { await respond(status) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.headline)
                Text(title).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? KlangradarTheme.accent : Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 12, style: .continuous))
            .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func load() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { isLoading = false; return }
        plan = (try? await repository.concertPlans(token: token))?.first { $0.id == planID }
        poll = (try? await repository.planPoll(planID, token: token)) ?? []
        isLoading = false
    }

    private func vote(_ option: PlanPollOption) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.votePlanOption(planID, eventID: option.event.id, token: token)
        Haptics.light()
        await load()
        await onChange?()
    }

    private func decide() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.decidePlanPoll(planID, token: token)
        Haptics.confirm()
        await load()
        await onChange?()
    }

    private func respond(_ status: String) async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        Haptics.light()
        try? await repository.respondConcertPlan(planID, status: status, token: token)
        await load()
        await SocialStore.shared.refresh()
        await onChange?()
    }

    private func invite() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.inviteToPlan(planID, friendIDs: Array(inviteSelection), token: token)
        inviteSelection = []
        showsInvite = false
        await load()
    }

    private func leave() async {
        guard let repository = SocialStore.shared.repository, let token = SocialStore.shared.token else { return }
        try? await repository.leaveConcertPlan(planID, token: token)
        await SocialStore.shared.refresh()
        await onChange?()
        dismiss()
    }
}

private struct PlanMeetingEditor: View {
    let plan: ConcertPlan
    let onSave: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var point = ""
    @State private var time = Date()
    @State private var hasTime = false
    @State private var note = ""

    var body: some View {
        Form {
            TextField("Treffpunkt", text: $point)
            Toggle("Uhrzeit", isOn: $hasTime)
            if hasTime { DatePicker("Um", selection: $time, displayedComponents: [.hourAndMinute]) }
            TextField("Notiz", text: $note, axis: .vertical).lineLimit(2...4)
        }
        .navigationTitle("Treffpunkt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") {
                    Task {
                        if let repository = SocialStore.shared.repository, let token = SocialStore.shared.token {
                            try? await repository.updateConcertPlan(plan.id, meetingPoint: point.isEmpty ? nil : point, meetingTime: hasTime ? time : nil, note: note.isEmpty ? nil : note, token: token)
                        }
                        await onSave()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            point = plan.meetingPoint ?? ""
            note = plan.note ?? ""
            hasTime = plan.meetingTime != nil
            time = plan.meetingTime ?? plan.event.start?.addingTimeInterval(-1800) ?? .now
        }
    }
}

/// Abstimmungsoptionen als flache Zeilen mit dünnem Stimmenbalken.
private struct PlanPollSection: View {
    let options: [PlanPollOption]
    let isOwner: Bool
    let onVote: (PlanPollOption) async -> Void
    let onDecide: () async -> Void

    var body: some View {
        let total = max(options.map(\.votes).reduce(0, +), 1)
        ForEach(options) { option in
            Button { Task { await onVote(option) } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.event.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                            Text(option.event.dateLine).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(option.votes)").font(.title3.weight(.semibold).monospacedDigit())
                            .foregroundStyle(option.mine ? KlangradarTheme.accent : .secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(uiColor: .tertiarySystemFill))
                            Capsule().fill(option.mine ? KlangradarTheme.accent : KlangradarTheme.accent.opacity(0.4))
                                .frame(width: max(4, proxy.size.width * CGFloat(option.votes) / CGFloat(total)))
                        }
                    }
                    .frame(height: 4)
                    if option.mine { Text("Deine Stimme").font(.caption2.weight(.semibold)).foregroundStyle(KlangradarTheme.accent) }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        if isOwner {
            Button("Jetzt entscheiden", systemImage: "checkmark.seal") { Task { await onDecide() } }
        }
    }
}
