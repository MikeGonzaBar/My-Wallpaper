import SwiftUI

@MainActor
struct DiagonalAppearanceTransition: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: UUID

    @State private var progress = 0.0
    @State private var isVisible = false
    @State private var animationToken = UUID()

    var body: some View {
        GeometryReader { proxy in
            if isVisible {
                Canvas { context, size in
                    let diagonal = hypot(size.width, size.height)
                    context.translateBy(x: size.width / 2, y: size.height / 2)
                    context.rotate(by: .degrees(45))
                    let leadingEdge = -diagonal * 2 + progress * diagonal * 4
                    context.fill(
                        Path(CGRect(
                            x: leadingEdge,
                            y: -diagonal * 2,
                            width: diagonal * 2,
                            height: diagonal * 4
                        )),
                        with: .color(RetroPalette.desktop)
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            playTransition()
        }
    }

    private func playTransition() {
        guard !reduceMotion else { return }
        let token = UUID()
        animationToken = token
        progress = 0
        isVisible = true
        withAnimation(.easeInOut(duration: 0.48)) {
            progress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard animationToken == token else { return }
            isVisible = false
        }
    }
}
