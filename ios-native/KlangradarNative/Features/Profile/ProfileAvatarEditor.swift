import SwiftUI
import UIKit

/// Aus ProfileView.swift extrahiert, damit der Profilbild-Editor auch im
/// Onboarding-Schritt "Persönliche Daten" wiederverwendet werden kann.
private enum ProfileImageSource: String, Identifiable {
    case library, camera
    var id: String { rawValue }
}

struct SelectedProfileImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ProfileAvatarEditor: View {
    @ObservedObject var auth: AuthStore
    let repository: UserRepository?
    var size: CGFloat = 58

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
                .frame(width: size, height: size)
                .clipShape(Circle())

                Image(systemName: "camera.fill")
                    .font(size >= 72 ? .caption.weight(.bold) : .caption2.weight(.bold))
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

struct ProfileImagePicker: UIViewControllerRepresentable {
    fileprivate let source: ProfileImageSource
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

struct CircularProfileCropView: View {
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

extension UIImage {
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
