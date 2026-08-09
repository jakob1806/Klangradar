import SwiftUI

/// SwiftUI-Äquivalent von CroppedNetworkImage (Flutter: app/lib/core/widgets/
/// cropped_network_image.dart) und CroppedImagePreview (Admin: components/
/// entity-gallery/cropped-image-preview.tsx) — rendert einen redaktionell
/// festgelegten Bildausschnitt (Anteile 0..1 des Originalbilds). `crop ==
/// nil` fällt auf ein normales zentriertes scaledToFill zurück (unverändertes
/// bisheriges Verhalten).
///
/// Technik: das Bild wird auf `1/crop.width` × `1/crop.height` der
/// Zielgröße vergrößert und um `-crop.x`/`-crop.y` seiner eigenen Größe
/// verschoben, sodass genau der gewählte Ausschnitt im sichtbaren Bereich
/// landet — dieselbe Ableitung wie in den anderen beiden Clients.
struct CroppedAsyncImage<Placeholder: View>: View {
    let url: URL?
    let crop: CropRect?
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: url) { image in
                if let crop, crop.width > 0, crop.height > 0 {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width / crop.width,
                            height: proxy.size.height / crop.height
                        )
                        .offset(
                            x: -crop.x * (proxy.size.width / crop.width),
                            y: -crop.y * (proxy.size.height / crop.height)
                        )
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .clipped()
                } else {
                    image.resizable().scaledToFill()
                }
            } placeholder: {
                placeholder()
            }
        }
    }
}
