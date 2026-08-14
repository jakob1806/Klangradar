import SwiftUI
import UIKit

struct ProfileView: View {
    let usesPreviewData: Bool
    @ObservedObject var auth: AuthStore
    let userRepository: UserRepository?
    let editorialRepository: EditorialRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository

    @AppStorage("appearance") private var appearance = "system"
    @State private var showsLogin = false
    @State private var hasEditorialAccess = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProfileOverview(
                        auth: auth,
                        repository: userRepository,
                        usesPreviewData: usesPreviewData
                    )
                }

                Section("Account") {
                    accountContent
                }

                Section("Dein Klangradar") {
                    NavigationLink {
                        FavoriteEventsView(auth: auth, repository: userRepository, eventRepository: eventRepository, contentRepository: contentRepository)
                    } label: {
                        Label("Favoriten", systemImage: "heart")
                    }
                    NavigationLink {
                        UserEventListsView(
                            auth: auth,
                            repository: userRepository,
                            eventRepository: eventRepository,
                            contentRepository: contentRepository
                        )
                    } label: {
                        Label("Meine Listen", systemImage: "rectangle.stack")
                    }
                    NavigationLink {
                        InterestsView(auth: auth, repository: userRepository)
                    } label: {
                        Label("Interessen", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        NotificationSettingsView(auth: auth, repository: userRepository)
                    } label: {
                        Label("Benachrichtigungen", systemImage: "bell")
                    }
                    NavigationLink {
                        HomeCategoryOrderView(userID: auth.userID)
                    } label: {
                        Label("Homepage anordnen", systemImage: "arrow.up.arrow.down")
                    }
                }

                if hasEditorialAccess, let editorialRepository {
                    Section {
                        NavigationLink {
                            EditorialDashboardView(auth: auth, repository: editorialRepository)
                        } label: {
                            Label("Redaktionsmodus", systemImage: "exclamationmark.shield.fill")
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Redaktion")
                    } footer: {
                        Text("Schnellkorrekturen wirken sich sofort auf alle Klangradar-Oberflächen aus.")
                    }
                }

                Section("Darstellung") {
                    Picker("Erscheinungsbild", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Hell").tag("light")
                        Text("Dunkel").tag("dark")
                    }
                }

                Section("Über Klangradar") {
                    Link("Datenschutz", destination: URL(string: "https://klangradar.app/datenschutz")!)
                    Link("Impressum", destination: URL(string: "https://klangradar.app/impressum")!)
                }
            }
            .navigationTitle("Profil")
            .navigationDestination(for: ConcertEvent.self) { event in
                EventDetailView(
                    event: event,
                    repository: eventRepository,
                    contentRepository: contentRepository
                )
            }
            .navigationDestination(for: EntityRoute.self) { route in
                EntityDetailView(route: route, repository: contentRepository)
            }
            .sheet(isPresented: $showsLogin) {
                EmailCodeLoginView(auth: auth)
            }
            .task(id: auth.accessToken) { await checkEditorialAccess() }
        }
    }

    @MainActor
    private func checkEditorialAccess() async {
        guard let editorialRepository, let token = auth.accessToken else {
            hasEditorialAccess = false
            return
        }
        hasEditorialAccess = await editorialRepository.hasAccess(token: token)
    }

    @ViewBuilder
    private var accountContent: some View {
        switch auth.state {
        case .unavailable:
            Label("Im Preview-Modus nicht verfügbar", systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView("Sitzung wird vorbereitet …")
        case .anonymous:
            Button("Mit E-Mail anmelden", systemImage: "envelope") {
                showsLogin = true
            }
        case let .authenticated(session):
            LabeledContent("Angemeldet als", value: session.user.email ?? "Klangradar Account")
            Button("Abmelden", role: .destructive) {
                Task { try? await auth.signOut() }
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Button("Erneut versuchen") {
                Task { await auth.bootstrap() }
            }
        }
    }
}

private struct ProfileOverview: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let usesPreviewData: Bool
    @State private var profile: KlangradarUserProfile?

    var body: some View {
        HStack(spacing: 14) {
            ProfileAvatarEditor(auth: auth, repository: repository)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .font(.headline)
                Text(accountLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if auth.userID != nil {
                NavigationLink {
                    AccountProfileEditView(auth: auth, repository: repository)
                } label: {
                    Text("Bearbeiten")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 6)
        .task(id: auth.userID) { await load() }
        .onAppear { Task { await load() } }
    }

    private var displayName: String {
        if let name = profile?.displayName, !name.isEmpty { return name }
        if let email = auth.session?.user.email { return email.split(separator: "@").first.map(String.init) ?? email }
        return usesPreviewData ? "Preview-Profil" : "Dein Profil"
    }

    private var accountLine: String {
        auth.session?.user.email ?? (usesPreviewData ? "Preview-Modus" : "Noch nicht angemeldet")
    }

    private func load() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else {
            profile = nil
            return
        }
        profile = try? await repository.profile(userID: userID, token: token)
    }
}

private struct AccountProfileEditView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var birthDate = Date()
    @State private var hasBirthDate = false
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Persönliche Angaben") {
                TextField("Name", text: $displayName)
                    .textContentType(.name)

                Toggle("Geburtstag hinterlegen", isOn: $hasBirthDate.animation())
                if hasBirthDate {
                    DatePicker(
                        "Geburtstag",
                        selection: $birthDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                }
            }

            Section("E-Mail-Adresse") {
                TextField("E-Mail-Adresse", text: $email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                Text("Nach einer Änderung sendet Supabase gegebenenfalls eine Bestätigung an die bisherige und die neue Adresse.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Neues Passwort") {
                SecureField("Mindestens 8 Zeichen", text: $password)
                    .textContentType(.newPassword)
                SecureField("Passwort wiederholen", text: $passwordConfirmation)
                    .textContentType(.newPassword)
                Text("Leer lassen, wenn das Passwort nicht geändert werden soll.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message {
                Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
        }
        .disabled(isLoading || isSaving)
        .overlay { if isLoading || isSaving { ProgressView() } }
        .navigationTitle("Profil bearbeiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { Task { await save() } }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        email = auth.session?.user.email ?? ""
        guard let repository, let userID = auth.userID, let token = auth.accessToken,
              let profile = try? await repository.profile(userID: userID, token: token) else { return }
        displayName = profile.displayName
        if let date = profile.birthDate {
            birthDate = date
            hasBirthDate = true
        }
    }

    private func save() async {
        errorMessage = nil
        message = nil
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanEmail.contains("@") else {
            errorMessage = "Bitte gib eine gültige E-Mail-Adresse ein."
            return
        }
        if !password.isEmpty {
            guard password.count >= 8 else {
                errorMessage = "Das neue Passwort muss mindestens 8 Zeichen lang sein."
                return
            }
            guard password == passwordConfirmation else {
                errorMessage = "Die eingegebenen Passwörter stimmen nicht überein."
                return
            }
        }

        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.updateProfile(
                displayName: displayName,
                birthDate: hasBirthDate ? birthDate : nil,
                userID: userID,
                token: token
            )
            if cleanEmail != auth.session?.user.email?.lowercased() {
                try await auth.updateEmail(cleanEmail)
            }
            if !password.isEmpty {
                try await auth.updatePassword(password)
                password = ""
                passwordConfirmation = ""
            }
            message = "Deine Änderungen wurden gespeichert."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct HomeCategoryOrderView: View {
    let userID: UUID?
    @State private var categories: [HomeRecommendationCategory]

    init(userID: UUID?) {
        self.userID = userID
        _categories = State(initialValue: HomeCategoryPreferences.order(for: userID))
    }

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Label(category.title, systemImage: category.symbol)
                }
                .onMove(perform: move)
            } header: {
                Text("Reihenfolge")
            } footer: {
                Text("Halte eine Kategorie am Griff rechts fest und verschiebe sie nach oben oder unten. Die Titelveranstaltung bleibt immer an erster Stelle.")
            }

            Section {
                Button("Standardreihenfolge wiederherstellen", systemImage: "arrow.counterclockwise") {
                    HomeCategoryPreferences.reset(for: userID)
                    categories = HomeRecommendationCategory.defaultOrder
                }
            }
        }
        .navigationTitle("Homepage anordnen")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .onAppear {
            categories = HomeCategoryPreferences.order(for: userID)
        }
        .onDisappear {
            // Zusätzlich zum sofortigen Speichern nach jedem Drag: schützt
            // vor einem SwiftUI-Neuaufbau während der Move-Animation.
            HomeCategoryPreferences.save(categories, for: userID)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        HomeCategoryPreferences.save(categories, for: userID)
    }
}

private enum ProfileImageSource: String, Identifiable {
    case library, camera
    var id: String { rawValue }
}

private struct SelectedProfileImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ProfileAvatarEditor: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?

    @State private var avatarURL: URL?
    @State private var source: ProfileImageSource?
    @State private var selectedImage: SelectedProfileImage?
    @State private var showsActions = false
    @State private var showsDeleteConfirmation = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            guard auth.userID != nil else { return }
            showsActions = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let avatarURL {
                        AsyncImage(url: avatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(KlangradarTheme.accent)
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(Circle())

                Image(systemName: "camera.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(KlangradarTheme.accent, in: Circle())
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }
            .overlay {
                if isWorking {
                    Circle()
                        .fill(.black.opacity(0.45))
                        .overlay { ProgressView().tint(.white) }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(auth.userID == nil || isWorking)
        .accessibilityLabel("Profilbild bearbeiten")
        .confirmationDialog("Profilbild", isPresented: $showsActions) {
            Button("Aus Mediathek auswählen", systemImage: "photo.on.rectangle") {
                source = .library
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Foto aufnehmen", systemImage: "camera") {
                    source = .camera
                }
            }
            if avatarURL != nil {
                Button("Profilbild löschen", systemImage: "trash", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Profilbild löschen?", isPresented: $showsDeleteConfirmation) {
            Button("Löschen", role: .destructive) { Task { await deleteAvatar() } }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Das aktuelle Profilbild wird dauerhaft entfernt.")
        }
        .alert(
            "Profilbild konnte nicht gespeichert werden",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .fullScreenCover(item: $source) { selectedSource in
            ProfileImagePicker(source: selectedSource) { image in
                source = nil
                // Erst den System-Picker vollständig schließen, bevor der
                // eigene runde Editor präsentiert wird. Zwei gleichzeitig
                // wechselnde fullScreenCover waren die Ursache dafür, dass
                // der Bearbeitungsablauf gelegentlich einfach abbrach.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    selectedImage = SelectedProfileImage(image: image.normalizedOrientation())
                }
            } onCancel: {
                source = nil
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $selectedImage) { selection in
            CircularProfileCropView(image: selection.image) { croppedImage in
                selectedImage = nil
                guard let data = croppedImage.jpegData(compressionQuality: 0.88) else {
                    errorMessage = "Das zugeschnittene Bild konnte nicht gelesen werden."
                    return
                }
                Task { await upload(data) }
            } onCancel: {
                selectedImage = nil
            }
        }
        .task(id: auth.userID) { await loadAvatar() }
    }

    private func loadAvatar() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else {
            avatarURL = nil
            return
        }
        avatarURL = try? await repository.profileAvatarURL(userID: userID, token: token)
    }

    @MainActor
    private func upload(_ data: Data) async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            avatarURL = try await repository.uploadProfileAvatar(
                data,
                userID: userID,
                token: token
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func deleteAvatar() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.deleteProfileAvatar(userID: userID, token: token)
            avatarURL = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProfileImagePicker: UIViewControllerRepresentable {
    let source: ProfileImageSource
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = source == .camera ? .camera : .photoLibrary
        picker.allowsEditing = false
        picker.mediaTypes = ["public.image"]
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onCancel()
                return
            }
            onImage(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private struct CircularProfileCropView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    let onSave: (UIImage) -> Void
    let onCancel: () -> Void

    init(image: UIImage, onSave: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        _image = State(initialValue: image)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let diameter = min(proxy.size.width - 40, 380)
                VStack(spacing: 28) {
                    Spacer(minLength: 20)

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: diameter, height: diameter)
                        .scaleEffect(zoom)
                        .offset(offset)
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                        .shadow(color: .black.opacity(0.24), radius: 16)
                        .gesture(dragGesture(diameter: diameter))
                        .simultaneousGesture(zoomGesture(diameter: diameter))

                    Text("Verschiebe und vergrößere das Bild innerhalb des runden Ausschnitts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    HStack(spacing: 28) {
                        Button("Links drehen", systemImage: "rotate.left") { rotate(clockwise: false) }
                        Button("Rechts drehen", systemImage: "rotate.right") { rotate(clockwise: true) }
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { onCancel(); dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Übernehmen") {
                            guard let cropped = croppedImage(diameter: diameter) else { return }
                            onSave(cropped)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
                .navigationTitle("Profilbild anpassen")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func dragGesture(diameter: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                offset = clamped(offset, diameter: diameter)
                baseOffset = offset
            }
    }

    private func zoomGesture(diameter: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in zoom = min(max(baseZoom * value.magnification, 1), 5) }
            .onEnded { _ in
                baseZoom = zoom
                offset = clamped(offset, diameter: diameter)
                baseOffset = offset
            }
    }

    private func clamped(_ proposed: CGSize, diameter: CGFloat) -> CGSize {
        let size = image.size
        let baseScale = max(diameter / size.width, diameter / size.height)
        let maxX = max(0, (size.width * baseScale * zoom - diameter) / 2)
        let maxY = max(0, (size.height * baseScale * zoom - diameter) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func rotate(clockwise: Bool) {
        image = image.rotated90(clockwise: clockwise)
        zoom = 1
        baseZoom = 1
        offset = .zero
        baseOffset = .zero
    }

    private func croppedImage(diameter: CGFloat) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let baseScale = max(diameter / width, diameter / height)
        let totalScale = baseScale * zoom
        let cropSide = min(min(width, height), diameter / totalScale)
        let originX = min(max(0, (width - cropSide) / 2 - offset.width / totalScale), width - cropSide)
        let originY = min(max(0, (height - cropSide) / 2 - offset.height / totalScale), height - cropSide)
        guard let crop = cgImage.cropping(to: CGRect(x: originX, y: originY, width: cropSide, height: cropSide)) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { _ in
            UIImage(cgImage: crop).draw(in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
    }
}

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }

    func rotated90(clockwise: Bool) -> UIImage {
        let targetSize = CGSize(width: size.height, height: size.width)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            let cg = context.cgContext
            cg.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)
            cg.rotate(by: clockwise ? .pi / 2 : -.pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}

private struct EmailCodeLoginView: View {
    @ObservedObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var code = ""
    @State private var didSendCode = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-Mail-Adresse", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)

                    if didSendCode {
                        TextField("Bestätigungscode", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                    }
                } footer: {
                    Text("Klangradar sendet einen einmaligen Anmeldecode. Ein Passwort ist nicht notwendig.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(didSendCode ? "Code bestätigen" : "Code senden") {
                        Task { await submit() }
                    }
                    .disabled(
                        isWorking
                            || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (didSendCode && code.isEmpty)
                    )
                }
            }
            .navigationTitle("Anmelden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            if didSendCode {
                try await auth.verifyEmailCode(code, email: email)
                dismiss()
            } else {
                try await auth.sendEmailCode(to: email)
                didSendCode = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FavoriteEventsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var events: [ConcertEvent] = []

    var body: some View {
        List(events) { event in
            NavigationLink(value: event) {
                Label(event.title, systemImage: "heart.fill")
            }
        }
            .overlay { if events.isEmpty { ContentUnavailableView("Noch keine Favoriten", systemImage: "heart", description: Text("Markierte Veranstaltungen erscheinen hier.")) } }
            .navigationTitle("Favoriten")
            .task {
                guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
                events = (try? await repository.favoriteEvents(userID: id, token: token)) ?? []
            }
    }
}

private struct UserEventListsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository

    @State private var lists: [UserEventList] = []
    @State private var showsCreate = false
    @State private var newName = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if auth.userID == nil {
                ContentUnavailableView(
                    "Anmeldung erforderlich",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("Melde dich im Profil an, um persönliche Konzertlisten zu erstellen und zu synchronisieren.")
                )
            } else if isLoading {
                ProgressView("Listen werden geladen …")
            } else if lists.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Listen", systemImage: "rectangle.stack")
                } description: {
                    Text("Erstelle eine Liste und füge anschließend beliebige kommende Konzerte hinzu.")
                } actions: {
                    Button("Neue Liste") { showsCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(lists) { list in
                        NavigationLink {
                            UserEventListDetailView(
                                initialList: list,
                                auth: auth,
                                repository: repository,
                                eventRepository: eventRepository,
                                contentRepository: contentRepository
                            )
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "music.note.list")
                                    .font(.title3)
                                    .foregroundStyle(KlangradarTheme.accent)
                                    .frame(width: 44, height: 44)
                                    .background(KlangradarTheme.accent.opacity(0.1), in: .rect(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(list.name).font(.headline)
                                    Text("\(list.events.count) \(list.events.count == 1 ? "Konzert" : "Konzerte")")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Meine Listen")
        .toolbar {
            if auth.userID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Neue Liste", systemImage: "plus") { showsCreate = true }
                }
            }
        }
        .alert("Neue Konzertliste", isPresented: $showsCreate) {
            TextField("Name der Liste", text: $newName)
            Button("Abbrechen", role: .cancel) { newName = "" }
            Button("Erstellen") { Task { await create() } }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Du kannst den Namen später jederzeit ändern.")
        }
        .alert("Listen konnten nicht aktualisiert werden", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Unbekannter Fehler") }
        .task { await load() }
        .onAppear { if !isLoading { Task { await load() } } }
    }

    private func load() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else {
            isLoading = false
            return
        }
        do {
            lists = try await repository.eventLists(userID: userID, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func create() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        do {
            if let list = try await repository.createEventList(name: newName, userID: userID, token: token) {
                lists.insert(list, at: 0)
            }
            newName = ""
        } catch { errorMessage = error.localizedDescription }
    }

    private func delete(at offsets: IndexSet) {
        guard let repository, let token = auth.accessToken else { return }
        let deleted = offsets.map { lists[$0] }
        lists.remove(atOffsets: offsets)
        Task {
            do {
                for list in deleted { try await repository.deleteEventList(id: list.id, token: token) }
            } catch {
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }
}

private struct UserEventListDetailView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    let contentRepository: any ContentRepository
    @State private var list: UserEventList
    @State private var showsPicker = false
    @State private var showsRename = false
    @State private var editedName: String

    init(
        initialList: UserEventList,
        auth: AuthStore,
        repository: UserRepository?,
        eventRepository: any EventRepository,
        contentRepository: any ContentRepository
    ) {
        _list = State(initialValue: initialList)
        _editedName = State(initialValue: initialList.name)
        self.auth = auth
        self.repository = repository
        self.eventRepository = eventRepository
        self.contentRepository = contentRepository
    }

    var body: some View {
        Group {
            if list.events.isEmpty {
                ContentUnavailableView {
                    Label("Liste ist leer", systemImage: "music.note.list")
                } description: {
                    Text("Wähle Konzerte aus dem gesamten kommenden Programm aus.")
                } actions: {
                    Button("Konzerte auswählen") { showsPicker = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(list.events) { event in
                        NavigationLink(value: event) { UserListEventRow(event: event) }
                            .swipeActions {
                                Button("Entfernen", role: .destructive) { Task { await remove(event) } }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Konzerte auswählen", systemImage: "plus") { showsPicker = true }
                Button("Umbenennen", systemImage: "pencil") {
                    editedName = list.name
                    showsRename = true
                }
            }
        }
        .sheet(isPresented: $showsPicker, onDismiss: { Task { await reload() } }) {
            EventListPicker(
                list: list,
                auth: auth,
                repository: repository,
                eventRepository: eventRepository
            )
        }
        .alert("Liste umbenennen", isPresented: $showsRename) {
            TextField("Name", text: $editedName)
            Button("Abbrechen", role: .cancel) {}
            Button("Sichern") { Task { await rename() } }
                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func reload() async {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        if let updated = try? await repository.eventLists(userID: userID, token: token).first(where: { $0.id == list.id }) {
            list = updated
            editedName = updated.name
        }
    }

    private func rename() async {
        guard let repository, let token = auth.accessToken else { return }
        try? await repository.renameEventList(id: list.id, name: editedName, token: token)
        await reload()
    }

    private func remove(_ event: ConcertEvent) async {
        guard let repository, let token = auth.accessToken else { return }
        let previous = Set(list.events.map(\.id))
        try? await repository.replaceEvents(in: list.id, selected: previous.subtracting([event.id]), previous: previous, token: token)
        await reload()
    }
}

private struct EventListPicker: View {
    let list: UserEventList
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    let eventRepository: any EventRepository
    @Environment(\.dismiss) private var dismiss
    @State private var events: [ConcertEvent] = []
    @State private var selected: Set<UUID>
    @State private var searchText = ""
    @State private var isSaving = false

    init(list: UserEventList, auth: AuthStore, repository: UserRepository?, eventRepository: any EventRepository) {
        self.list = list
        self.auth = auth
        self.repository = repository
        self.eventRepository = eventRepository
        _selected = State(initialValue: Set(list.events.map(\.id)))
    }

    private var filtered: [ConcertEvent] {
        searchText.isEmpty ? events : events.filter {
            $0.title.localizedStandardContains(searchText) || $0.venueName.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { event in
                Button { toggle(event.id) } label: {
                    HStack(spacing: 12) {
                        EventArtwork(event: event)
                            .frame(width: 64, height: 54)
                            .clipped()
                            .clipShape(.rect(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                            Text(event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: selected.contains(event.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected.contains(event.id) ? KlangradarTheme.accent : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay { if events.isEmpty { ProgressView("Konzerte werden geladen …") } }
            .navigationTitle("Konzerte auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Titel oder Ort")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Speichert …" : "Fertig") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .task {
                let loaded = (try? await eventRepository.allUpcomingEvents()) ?? []
                events = (try? await eventRepository.enrichingImages(in: loaded)) ?? loaded
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func save() async {
        guard let repository, let token = auth.accessToken else { return }
        isSaving = true
        let previous = Set(list.events.map(\.id))
        try? await repository.replaceEvents(in: list.id, selected: selected, previous: previous, token: token)
        isSaving = false
        dismiss()
    }
}

private struct UserListEventRow: View {
    let event: ConcertEvent

    var body: some View {
        HStack(spacing: 12) {
            EventArtwork(event: event)
                .frame(width: 78, height: 64)
                .clipped()
                .clipShape(.rect(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.headline).lineLimit(2)
                Text(event.dateLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct InterestsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @State private var category: InterestCategory = .genre
    @State private var options: [InterestOption] = []
    @State private var selected: Set<String> = []
    @State private var searchText = ""

    private var filteredOptions: [InterestOption] {
        searchText.isEmpty ? options : options.filter { $0.label.localizedStandardContains(searchText) }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(InterestCategory.allCases, id: \.self) { item in
                            Button { category = item } label: {
                                Label(item.title, systemImage: item.systemImage)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(category == item ? KlangradarTheme.accent : Color.secondary.opacity(0.12), in: .capsule)
                                    .foregroundStyle(category == item ? .white : .primary)
                            }.buttonStyle(.plain)
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            Section("\(category.title) · \(selected.count) ausgewählt") {
                ForEach(filteredOptions) { option in
                    Button { toggle(option.id) } label: {
                        HStack { Text(option.label).foregroundStyle(.primary); Spacer(); Image(systemName: selected.contains(option.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(option.id) ? KlangradarTheme.accent : .secondary) }
                    }
                }
            }
        }
        .navigationTitle("Interessen")
        .searchable(text: $searchText, prompt: "\(category.title) durchsuchen")
        .task(id: category) { searchText = ""; await load() }
    }

    private func load() async {
        guard let repository else { return }
        options = (try? await repository.interestOptions(category)) ?? []
        guard let id = auth.userID, let token = auth.accessToken else { return }
        selected = (try? await repository.selectedInterests(category, userID: id, token: token)) ?? []
    }

    private func toggle(_ id: String) {
        guard let repository, let userID = auth.userID, let token = auth.accessToken else { return }
        let newValue = !selected.contains(id)
        if newValue { selected.insert(id) } else { selected.remove(id) }
        Task { try? await repository.setInterest(category, id: id, selected: newValue, userID: userID, token: token) }
    }
}

private struct NotificationSettingsView: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    @State private var preferences = NotificationPreferences()

    var body: some View {
        Form {
            Toggle("Neue passende Veranstaltungen", isOn: binding(\.newMatchingEvents, "new_matching_events"))
            Toggle("Preisänderungen", isOn: binding(\.priceChanges, "price_changes"))
            Toggle("Fast ausverkauft", isOn: binding(\.almostSoldOut, "almost_sold_out"))
            Toggle("Erinnerung am Vortag", isOn: binding(\.reminderDayBefore, "reminder_day_before"))
            // Deckt jetzt auch gefolgte Personen/Orte ab (siehe
            // notify-followed-entity-events), die Datenbankspalte heißt
            // aus historischen Gründen weiter "followed_ensemble_new_event".
            Toggle("Neue Termine gefolgter Personen, Ensembles & Orte", isOn: binding(\.followedEnsembleNewEvent, "followed_ensemble_new_event"))
        }
        .navigationTitle("Benachrichtigungen")
        .task {
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            preferences = (try? await repository.preferences(userID: id, token: token)) ?? NotificationPreferences()
        }
    }

    private func binding(_ keyPath: WritableKeyPath<NotificationPreferences, Bool>, _ column: String) -> Binding<Bool> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in
            preferences[keyPath: keyPath] = value
            guard let repository, let id = auth.userID, let token = auth.accessToken else { return }
            Task { try? await repository.setPreference(userID: id, token: token, column: column, value: value) }
        })
    }
}
