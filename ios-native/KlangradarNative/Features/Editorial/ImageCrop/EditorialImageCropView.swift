import SwiftUI

/// Punkt 19, "Native Bild-Crop": exakt dieselbe Mathematik wie admin's
/// CropTool (admin/src/components/entity-gallery/crop-tool.tsx) — Ziehen
/// zum Verschieben + Zoom-Regler, daraus ein normalisierter Ausschnitt
/// (Anteile 0..1). Web-Kompatibilität ist hier wörtlich gemeint: dieselbe
/// Formel, dieselbe resultierende CropRect, damit ein in der App gesetzter
/// Ausschnitt im Admin (und umgekehrt) identisch aussieht.
enum EditorialCropMath {
    /// Größter Ausschnitt im Zielseitenverhältnis, zentriert im Originalbild
    /// — Ausgangszustand, bevor die Redaktion selbst zieht/zoomt (siehe
    /// admin/src/components/entity-gallery/crop-math.ts#defaultCropRect).
    static func defaultCrop(naturalWidth: Double, naturalHeight: Double, aspect: Double) -> CropRect {
        let imageAspect = naturalWidth / naturalHeight
        if imageAspect > aspect {
            let width = aspect / imageAspect
            return CropRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }
        let height = imageAspect / aspect
        return CropRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
    }
}

struct EditorialImageCropView: View {
    let image: UIImage
    let initialCrop: CropRect?
    let aspect: Double
    let isCircular: Bool
    let title: String
    let onSave: (CropRect) async throws -> Void
    let onReset: (() async throws -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: Double = 1
    @State private var offset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let frameWidth: Double = 300
    private var frameHeight: Double { Self.frameWidth / aspect }
    private var naturalWidth: Double { max(image.size.width, 1) }
    private var naturalHeight: Double { max(image.size.height, 1) }
    private var baseScale: Double { max(Self.frameWidth / naturalWidth, frameHeight / naturalHeight) }
    private var scale: Double { baseScale * zoom }
    private var renderedWidth: Double { naturalWidth * scale }
    private var renderedHeight: Double { naturalHeight * scale }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: renderedWidth, height: renderedHeight)
                        .offset(offset)
                }
                .frame(width: Self.frameWidth, height: frameHeight)
                .background(Color.black)
                .clipShape(isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = clamp(CGSize(width: dragStartOffset.width + value.translation.width, height: dragStartOffset.height + value.translation.height))
                        }
                        .onEnded { _ in dragStartOffset = offset }
                )

                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { zoom }, set: { setZoom($0) }), in: 1...3)
                            .tint(KlangradarTheme.accent)
                        Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .background(EditorialBackground())
            .navigationTitle("Ausschnitt festlegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .overlay { if isSaving { ProgressView() } }
            .safeAreaInset(edge: .bottom) {
                if onReset != nil {
                    Button("Auf Standard zurücksetzen", role: .destructive) { Task { await reset() } }
                        .font(.footnote)
                        .padding(.bottom, 12)
                        .disabled(isSaving)
                }
            }
            .alert("Fehler", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .onAppear { setUpInitialState() }
        }
    }

    private func setUpInitialState() {
        let crop = initialCrop ?? EditorialCropMath.defaultCrop(naturalWidth: naturalWidth, naturalHeight: naturalHeight, aspect: aspect)
        let targetScale = Self.frameWidth / crop.width / naturalWidth
        zoom = max(1, targetScale / baseScale)
        let renderedW = naturalWidth * baseScale * zoom
        let renderedH = naturalHeight * baseScale * zoom
        offset = clamp(CGSize(width: -crop.x * naturalWidth * (renderedW / naturalWidth), height: -crop.y * naturalHeight * (renderedH / naturalHeight)))
        dragStartOffset = offset
    }

    private func clamp(_ proposed: CGSize) -> CGSize {
        CGSize(
            width: min(0, max(Self.frameWidth - renderedWidth, proposed.width)),
            height: min(0, max(frameHeight - renderedHeight, proposed.height))
        )
    }

    private func setZoom(_ next: Double) {
        let scaleRatio = next / zoom
        let newRenderedW = renderedWidth * scaleRatio
        let newRenderedH = renderedHeight * scaleRatio
        let centerX = offset.width + renderedWidth / 2
        let centerY = offset.height + renderedHeight / 2
        zoom = next
        let proposed = CGSize(width: centerX * scaleRatio - newRenderedW / 2, height: centerY * scaleRatio - newRenderedH / 2)
        offset = clamp(proposed)
        dragStartOffset = offset
    }

    private func currentCrop() -> CropRect {
        CropRect(
            x: -offset.width / renderedWidth,
            y: -offset.height / renderedHeight,
            width: Self.frameWidth / renderedWidth,
            height: frameHeight / renderedHeight
        )
    }

    @MainActor private func save() async {
        isSaving = true; defer { isSaving = false }
        do { try await onSave(currentCrop()); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }

    @MainActor private func reset() async {
        guard let onReset else { return }
        isSaving = true; defer { isSaving = false }
        do { try await onReset(); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

