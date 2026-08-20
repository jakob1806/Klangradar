import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Bildauswahl aus Fotomediathek oder Dateien, mit gemeinsamer JPEG-
/// Vorverarbeitung (Downscale + Kompression) — genutzt von CreateFlows,
/// EntityEditor (Profilbild) und Media (Galerie).
struct EditorialImagePickerButtons: View {
    let onImages: ([Data]) -> Void
    let onError: (String) -> Void
    var allowsMultipleSelection = true
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showsFileImporter = false
    @State private var isPreparing = false

    var body: some View {
        HStack {
            PhotosPicker(selection: $photoItems, maxSelectionCount: allowsMultipleSelection ? 20 : 1, matching: .images) {
                Label("Fotomediathek", systemImage: "photo.on.rectangle")
            }
            Button("Dateien", systemImage: "folder") { showsFileImporter = true }
        }
        .buttonStyle(.bordered)
        .tint(KlangradarTheme.accent)
        .disabled(isPreparing)
        .overlay(alignment: .trailing) { if isPreparing { ProgressView() } }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                isPreparing = true
                defer { isPreparing = false; photoItems = [] }
                do {
                    var prepared: [Data] = []
                    for item in items {
                        guard let data = try await item.loadTransferable(type: Data.self), let jpeg = Self.preparedJPEG(from: data) else {
                            throw EditorialImageError.unreadable
                        }
                        prepared.append(jpeg)
                    }
                    onImages(prepared)
                } catch { onError(error.localizedDescription) }
            }
        }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: allowsMultipleSelection) { result in
            do {
                let urls = try result.get()
                var prepared: [Data] = []
                for url in urls {
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard let jpeg = Self.preparedJPEG(from: data) else { throw EditorialImageError.unreadable }
                    prepared.append(jpeg)
                }
                onImages(prepared)
            } catch { onError(error.localizedDescription) }
        }
    }

    private static func preparedJPEG(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maximumDimension: CGFloat = 2400
        let longestSide = max(image.size.width, image.size.height)
        let scale = min(1, maximumDimension / longestSide)
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: 0.86)
    }
}

enum EditorialImageError: LocalizedError {
    case unreadable
    var errorDescription: String? { "Das ausgewählte Bild konnte nicht verarbeitet werden." }
}
