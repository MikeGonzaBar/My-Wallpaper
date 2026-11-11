import AppKit
import SwiftUI

struct VideoLibraryDetailsView: View {
    @ObservedObject var store: WallpaperStore
    let video: ManagedVideo
    let usageCount: Int
    let addDestinationName: String?
    let onAdd: () -> Void
    let onReplace: () -> Void
    let onRemove: () -> Void

    private var isUnavailable: Bool { !VideoLibrarySnapshot.isReadableVideoFile(video.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LibraryVideoPreview(videoURL: URL(fileURLWithPath: video.playbackPath(
                quality: store.settings.playbackQuality,
                profile: store.settings.optimizationProfile
            )))
            Text(video.displayName.uppercased())
                .font(RetroFont.label(size: 10))
                .lineLimit(2)
            Text(VideoLibrarySnapshot.metadataText(for: video))
                .font(RetroFont.body(size: 9))
            if isUnavailable {
                Text("ORIGINAL MISSING OR UNREADABLE. CHOOSE A REPLACEMENT TO KEEP ITS DISPLAY ASSIGNMENTS.")
                    .font(RetroFont.body(size: 9))
            }
            Button(store.recoveringVideoIDs.contains(video.id) ? "REPLACING…" : "REPLACE VIDEO…", action: onReplace)
                .buttonStyle(RetroButtonStyle(compact: true))
                .disabled(store.recoveringVideoIDs.contains(video.id))
            optimizationStatus
            RetroDivider()
            Text("ORIGINAL: \(VideoLibraryStorage.formatted(VideoLibraryStorage.fileSize(video.path)))")
                .font(RetroFont.body(size: 8))
            Text("PERFORMANCE COPY: \(VideoLibraryStorage.formatted(video.optimizedPath.map(VideoLibraryStorage.fileSize) ?? 0))")
                .font(RetroFont.body(size: 8))
            Text("USED ON \(usageCount) DISPLAY\(usageCount == 1 ? "" : "S")")
                .font(RetroFont.label(size: 9))
            ForEach(store.settings.screens.filter {
                $0.videoIDs.contains(video.id) || $0.stashedPlaylistVideoIDs.contains(video.id)
            }) { screen in
                Text("■ \(screen.screenName.uppercased())").font(RetroFont.body(size: 8))
            }
            if usageCount == 0 {
                Text("NOT ASSIGNED TO A DISPLAY").font(RetroFont.body(size: 8))
            }
            Button(addDestinationName.map { "ADD TO \($0.uppercased())" } ?? "CONNECT A DISPLAY", action: onAdd)
                .buttonStyle(RetroButtonStyle(primary: true, compact: true))
                .disabled(addDestinationName == nil)
            Button("REVEAL IN FINDER") { NSWorkspace.shared.activateFileViewerSelecting([video.url]) }
                .buttonStyle(RetroButtonStyle(compact: true))
                .disabled(isUnavailable)
            if usageCount == 0 {
                Button("REMOVE FROM LIBRARY…", role: .destructive, action: onRemove)
                    .buttonStyle(RetroButtonStyle(compact: true))
                    .disabled(store.recoveringVideoIDs.contains(video.id))
            }
        }
    }

    @ViewBuilder
    private var optimizationStatus: some View {
        let state = store.optimization.state(for: video, profile: store.settings.optimizationProfile)
        if let state {
            Text("PERFORMANCE COPY: \(state.title.uppercased())").font(RetroFont.label(size: 9))
            if case let .failed(reason) = state {
                Text(reason).font(RetroFont.body(size: 9)).textSelection(.enabled)
            }
            if case .paused = state {
                Text("RESUMES AFTER PREVIEW OR SCREEN SAVER PLAYBACK.").font(RetroFont.body(size: 8))
            }
        }
        if store.settings.playbackQuality == .performance, !isUnavailable {
            switch state {
            case .failed, nil:
                Button(state == nil ? "OPTIMIZE THIS VIDEO" : "RETRY PERFORMANCE COPY") {
                    store.retryOptimization(for: video.id)
                }
                .buttonStyle(RetroButtonStyle(compact: true))
            default: EmptyView()
            }
        }
    }
}
