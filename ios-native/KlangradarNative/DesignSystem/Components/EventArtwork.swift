import SwiftUI

struct FullScreenImageReference: Identifiable, Hashable {
    let url: URL
    let title: String

    var id: String { url.absoluteString }
}

struct FullScreenImageViewer: View {
    let image: FullScreenImageReference
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: image.url) { phase in
                switch phase {
                case let .success(value):
                    value
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { gesture in
                                    scale = min(max(settledScale * gesture.magnification, 1), 5)
                                }
                                .onEnded { _ in settledScale = scale }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.snappy) {
                                scale = scale > 1 ? 1 : 2.5
                                settledScale = scale
                            }
                        }
                case .empty:
                    ProgressView().tint(.white)
                case .failure:
                    ContentUnavailableView("Bild nicht verfügbar", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.white)
                @unknown default:
                    EmptyView()
                }
            }
            .accessibilityLabel(image.title)

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: .circle)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Bild schließen")
                }
                Spacer()
                Text(image.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            .padding()
        }
        .statusBarHidden()
    }
}

struct EventArtwork: View {
    let event: ConcertEvent

    var body: some View {
        AsyncImage(url: event.primaryImageURL) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                placeholder
            case .empty:
                placeholder
                    .overlay { ProgressView().tint(.white) }
            @unknown default:
                placeholder
            }
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [KlangradarTheme.deepInk, KlangradarTheme.accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note.list")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}
