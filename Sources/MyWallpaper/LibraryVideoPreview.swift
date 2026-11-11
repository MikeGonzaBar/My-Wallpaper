import AVKit
import SwiftUI

struct LibraryVideoPreview: View {
    let videoURL: URL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var playback = LibraryVideoPlayback()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LibraryPlayerView(player: playback.player)
                .frame(width: 228, height: 128)
                .overlay {
                    if playback.isLoading {
                        ProgressView().controlSize(.small).padding(8).background(.regularMaterial)
                    }
                }
                .accessibilityLabel("Selected video preview")
            if let error = playback.errorMessage {
                Text("PREVIEW UNAVAILABLE: \(error)")
                    .font(RetroFont.body(size: 9))
                    .textSelection(.enabled)
            }
        }
        .onAppear { playback.load(videoURL, isActive: scenePhase == .active) }
        .onChange(of: videoURL) { _, url in
            playback.load(url, isActive: scenePhase == .active)
        }
        .onChange(of: scenePhase) { _, phase in
            playback.setActive(phase == .active)
        }
        .onDisappear { playback.stop() }
    }
}

struct LibraryPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = false
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player = nil
    }
}
