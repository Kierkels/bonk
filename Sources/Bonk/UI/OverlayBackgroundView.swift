import SwiftUI
import AppKit

/// Live frosted-glass blur van wat er achter het venster staat (je scherm).
/// Vereist géén schermopname-permissie.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// De achtergrond van het overlay, deelbaar tussen het echte scherm en de preview.
struct OverlayBackgroundView: View {
    let appearance: OverlayAppearance
    var animated: Bool = true
    /// Vastgelegde schermfoto voor de instelbare blur. Ontbreekt deze, dan wordt
    /// teruggevallen op de (vaste) frosted-glass via NSVisualEffectView.
    var blurImage: NSImage? = nil

    @State private var pulse = false

    var body: some View {
        ZStack {
            content
            // Scrim voor leesbaarheid van de witte tekst.
            Color.black.opacity(appearance.scrim)
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch appearance.style {
        case .gradient:
            gradient
        case .solid:
            Color(hex: appearance.accentHex)
        case .blur:
            if let blurImage {
                Image(nsImage: blurImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: appearance.blurRadius, opaque: true)
            } else {
                VisualEffectBackground()
            }
        case .image:
            imageBackground
        }
    }

    private var gradient: some View {
        let base = Color(hex: appearance.accentHex)
        return ZStack {
            LinearGradient(
                colors: [
                    base.blended(with: .black, fraction: 0.55),
                    base,
                    base.blended(with: .systemPink, fraction: 0.35)
                ],
                startPoint: pulse ? .topLeading : .bottomLeading,
                endPoint: pulse ? .bottomTrailing : .topTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(0.18), .clear],
                center: .center,
                startRadius: 10,
                endRadius: pulse ? 620 : 520
            )
        }
    }

    @ViewBuilder
    private var imageBackground: some View {
        if let path = appearance.imagePath, let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
        } else {
            // Fallback als er (nog) geen afbeelding is gekozen.
            gradient
        }
    }
}
