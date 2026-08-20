import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Bildergalerie-Verwaltung für Events und Entities (Punkt 15, "Media") —
/// genutzt von EntityEditor und EventEditor.
struct EditorialGalleryEditor: View {
    @ObservedObject var auth: AuthStore
    let repository: EditorialRepository
    let originType: String
    let originID: UUID
    let onPrimaryChanged: (String?) -> Void

    @State private var images: [EditorialGalleryImage] = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bildergalerie", systemImage: "photo.stack")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !images.isEmpty { Text("\(images.count)").font(.caption).foregroundStyle(.secondary) }
            }

            EditorialImagePickerButtons { selectedData in
                Task { await add(selectedData) }
            } onError: { errorMessage = $0 }

            if isWorking {
                ProgressView("Bilder werden verarbeitet …")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if images.isEmpty {
                Text("Noch keine Galeriebilder vorhanden.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                            VStack(alignment: .leading, spacing: 8) {
                                CachedAsyncImage(url: URL(string: image.url)) { phase in
                                    if case let .success(loaded) = phase {
                                        loaded.resizable().scaledToFill()
                                    } else {
                                        Color.secondary.opacity(0.1).overlay { ProgressView() }
                                    }
                                }
                                .frame(width: 180, height: 112)
                                .clipShape(.rect(cornerRadius: 12)).clipped()

                                if index == 0 {
                                    Label("Titelbild", systemImage: "star.fill")
                                        .font(.caption.weight(.semibold)).foregroundStyle(KlangradarTheme.accent)
                                } else {
                                    Button("Als Titelbild", systemImage: "star") { Task { await makePrimary(image) } }
                                        .font(.caption)
                                }
                                Button("Löschen", systemImage: "trash", role: .destructive) { Task { await delete(image) } }
                                    .font(.caption)
                            }
                            .padding(10)
                            .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 14))
                        }
                    }
                }
            }
        }
        .task { await load() }
        .alert("Bilder konnten nicht geändert werden", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @MainActor private func load() async {
        guard let token = auth.accessToken else { return }
        do {
            images = try await repository.galleryImages(originType: originType, originID: originID, token: token)
            if let primaryURL = images.first?.url { onPrimaryChanged(primaryURL) }
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func add(_ data: [Data]) async {
        guard let token = auth.accessToken, let actor = auth.userID, !data.isEmpty else { return }
        isWorking = true; defer { isWorking = false }
        do {
            images = try await repository.addGalleryImages(data: data, originType: originType, originID: originID, actor: actor, token: token)
            onPrimaryChanged(images.first?.url)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func makePrimary(_ image: EditorialGalleryImage) async {
        guard let token = auth.accessToken else { return }
        isWorking = true; defer { isWorking = false }
        do {
            try await repository.setPrimaryGalleryImage(image, originType: originType, originID: originID, token: token)
            images = try await repository.galleryImages(originType: originType, originID: originID, token: token)
            onPrimaryChanged(images.first?.url)
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func delete(_ image: EditorialGalleryImage) async {
        guard let token = auth.accessToken, let actor = auth.userID else { return }
        isWorking = true; defer { isWorking = false }
        do {
            images = try await repository.deleteGalleryImage(image, originType: originType, originID: originID, actor: actor, token: token)
            onPrimaryChanged(images.first?.url)
        } catch { errorMessage = error.localizedDescription }
    }
}
