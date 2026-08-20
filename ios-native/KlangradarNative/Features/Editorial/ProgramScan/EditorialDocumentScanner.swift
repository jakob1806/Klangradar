import SwiftUI
import VisionKit

/// Kamera-Schritt von Punkt 18 (Programmheft-Scan) — VNDocumentCameraViewController
/// liefert bereits automatische Kantenerkennung/Perspektivkorrektur/Kontrast,
/// exakt was für ein fotografiertes Programmheft gebraucht wird, ohne das
/// selbst nachzubauen.
struct EditorialDocumentScanner: UIViewControllerRepresentable {
    let onScanned: ([UIImage]) -> Void
    let onCancelled: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScanned: onScanned, onCancelled: onCancelled) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanned: ([UIImage]) -> Void
        let onCancelled: () -> Void

        init(onScanned: @escaping ([UIImage]) -> Void, onCancelled: @escaping () -> Void) {
            self.onScanned = onScanned
            self.onCancelled = onCancelled
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for pageIndex in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: pageIndex))
            }
            onScanned(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancelled()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onCancelled()
        }
    }
}
