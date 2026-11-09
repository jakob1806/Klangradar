// Erstellt von Claude Code (09.11.2026): Bildausschnitt für den flachen
// Wallet-Streifen. Findet das Motiv (Gesichter, sonst Vision-Aufmerksamkeit)
// und merkt sich eine vom Nutzer verschobene Position je Konzert.
import SwiftUI
import UIKit
import Vision

enum ImageFocus {
    private static func key(_ id: UUID) -> String { "walletFocus.\(id.uuidString.lowercased())" }

    static func stored(for eventID: UUID) -> CGPoint? {
        guard let values = UserDefaults.standard.array(forKey: key(eventID)) as? [Double], values.count == 2 else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    static func store(_ point: CGPoint, for eventID: UUID) {
        UserDefaults.standard.set([Double(point.x), Double(point.y)], forKey: key(eventID))
    }

    /// Motivmitte, normiert 0…1 mit Ursprung oben links.
    static func detect(in image: UIImage) async -> CGPoint {
        guard let cg = image.cgImage else { return CGPoint(x: 0.5, y: 0.35) }
        return await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cg)
            let faces = VNDetectFaceRectanglesRequest()
            try? handler.perform([faces])
            if let results = faces.results, !results.isEmpty {
                // Alle Gesichter umschließen, etwas unter der Stirn ansetzen.
                let box = results.map(\.boundingBox).reduce(results[0].boundingBox) { $0.union($1) }
                return CGPoint(x: box.midX, y: min(1, 1 - box.midY + box.height * 0.15))
            }
            let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
            try? handler.perform([saliency])
            if let object = (saliency.results?.first)?.salientObjects?.max(by: { $0.confidence < $1.confidence }) {
                let b = object.boundingBox
                return CGPoint(x: b.midX, y: 1 - b.midY)
            }
            return CGPoint(x: 0.5, y: 0.35)
        }.value
    }
}

/// Bild füllt einen flachen Streifen; der Ausschnitt folgt `focus` und lässt
/// sich per Ziehen verschieben.
struct FocusedStripImage: View {
    let image: UIImage
    @Binding var focus: CGPoint
    var onCommit: (CGPoint) -> Void = { _ in }
    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.size
            let scale = max(frame.width / image.size.width, frame.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let maxX = max(0, size.width - frame.width), maxY = max(0, size.height - frame.height)
            let x = min(maxX, max(0, size.width * focus.x - frame.width / 2))
            let y = min(maxY, max(0, size.height * focus.y - frame.height / 2))
            Image(uiImage: image).resizable()
                .frame(width: size.width, height: size.height)
                .offset(x: -x, y: -y)
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .clipped()
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let start = dragStart ?? focus
                        if dragStart == nil { dragStart = focus }
                        focus = CGPoint(
                            x: min(1, max(0, start.x - value.translation.width / max(size.width, 1))),
                            y: min(1, max(0, start.y - value.translation.height / max(size.height, 1))))
                    }
                    .onEnded { _ in dragStart = nil; onCommit(focus) })
        }
    }
}
