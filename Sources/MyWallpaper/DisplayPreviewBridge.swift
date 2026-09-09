import AppKit
import AVFoundation
import SwiftUI

@MainActor
struct PlayerPreviewView: NSViewRepresentable {
    let player: AVPlayer
    let scaling: VideoScaling
    @Binding var isReadyForDisplay: Bool

    func makeNSView(context: Context) -> PlayerPreviewNSView {
        let view = PlayerPreviewNSView(player: player, scaling: scaling)
        configureReadinessHandler(for: view)
        return view
    }

    func updateNSView(_ nsView: PlayerPreviewNSView, context: Context) {
        configureReadinessHandler(for: nsView)
        nsView.update(player: player, scaling: scaling)
    }

    private func configureReadinessHandler(for view: PlayerPreviewNSView) {
        view.onReadyForDisplayChange = { ready in
            if isReadyForDisplay != ready {
                isReadyForDisplay = ready
            }
        }
    }
}

@MainActor
final class PlayerPreviewNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var readinessObservation: NSKeyValueObservation?
    var onReadyForDisplayChange: ((Bool) -> Void)? {
        didSet { reportReadiness(playerLayer.isReadyForDisplay) }
    }

    init(player: AVPlayer, scaling: VideoScaling) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        readinessObservation = playerLayer.observe(
            \.isReadyForDisplay,
            options: [.initial, .new]
        ) { [weak self] layer, _ in
            let ready = layer.isReadyForDisplay
            Task { @MainActor [weak self] in
                self?.reportReadiness(ready)
            }
        }
        update(player: player, scaling: scaling)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func update(player: AVPlayer, scaling: VideoScaling) {
        if playerLayer.player !== player {
            reportReadiness(false)
            playerLayer.player = player
        }
        playerLayer.videoGravity = scaling == .fill ? .resizeAspectFill : .resizeAspect
    }

    private func reportReadiness(_ ready: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onReadyForDisplayChange?(ready)
        }
    }
}

struct PreviewLoadingTip: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("LOADING VIDEO…")
                .font(RetroFont.label(size: 11))
            Text("FIRST FRAME MAY TAKE 1–2 SECONDS.")
                .font(RetroFont.body(size: 9))
                .foregroundStyle(RetroPalette.secondaryInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RetroPalette.paper)
        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
        .background {
            Rectangle()
                .fill(RetroPalette.ink)
                .offset(x: 3, y: 3)
        }
        .padding(.trailing, 3)
        .padding(.bottom, 3)
        .accessibilityElement(children: .combine)
    }
}
