import SwiftUI

struct PerformanceModePanel: View {
    @ObservedObject var store: WallpaperStore

    var body: some View {
        RetroWindow(title: "PERFORMANCE MODE") {
            VStack(alignment: .leading, spacing: 14) {
                RetroChoiceBar(
                    values: VideoPlaybackQuality.allCases,
                    selected: store.settings.playbackQuality,
                    accessibilityLabel: "Playback quality",
                    title: { $0.title.uppercased() },
                    accessibilityTitle: { $0.title },
                    onSelect: store.setPlaybackQuality
                )

                Text(description)
                    .font(RetroFont.body(size: 9))
                    .foregroundStyle(RetroPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if store.settings.playbackQuality == .performance {
                    RetroDivider()
                    Text("OPTIMIZED COPY QUALITY")
                        .font(RetroFont.label(size: 10))
                    RetroChoiceBar(
                        values: VideoOptimizationProfile.allCases,
                        selected: store.settings.optimizationProfile,
                        accessibilityLabel: "Optimization profile",
                        title: { $0.title.uppercased() },
                        accessibilityTitle: { $0.title },
                        onSelect: store.setOptimizationProfile
                    )
                    optimizationStatus
                } else if store.demandingVideoCount > 0 {
                    Text("⚠ \(store.demandingVideoCount) HIGH-LOAD VIDEO(S) MAY STUTTER IN ORIGINAL QUALITY.")
                        .font(RetroFont.label(size: 9))
                }
            }
        }
    }

    @ViewBuilder
    private var optimizationStatus: some View {
        if let progress = store.optimizationProgress {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress.overallFraction)
                    .progressViewStyle(.linear)
                    .tint(RetroPalette.ink)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OPTIMIZING \(min(progress.completedCount + 1, progress.totalCount)) OF \(progress.totalCount)")
                            .font(RetroFont.label(size: 9))
                        if let currentVideoName = progress.currentVideoName {
                            Text(currentVideoName.uppercased())
                                .font(RetroFont.body(size: 8))
                                .foregroundStyle(RetroPalette.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button("CANCEL") { store.cancelOptimization() }
                        .buttonStyle(RetroButtonStyle(compact: true))
                }
            }
        } else {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(store.optimizedVideoCount) OF \(store.settings.videos.count) VIDEO(S) READY")
                        .font(RetroFont.label(size: 9))
                    Text(storageSummary)
                        .font(RetroFont.body(size: 8))
                        .foregroundStyle(RetroPalette.secondaryInk)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button("OPTIMIZE EXISTING VIDEOS") { store.optimizeExistingVideos() }
                        .buttonStyle(RetroButtonStyle(primary: true, compact: true))
                        .disabled(store.settings.videos.isEmpty)
                    if store.optimizedVideoCount > 0 {
                        Button("DELETE PERFORMANCE COPIES") { store.deleteOptimizedCopies() }
                            .buttonStyle(RetroButtonStyle(compact: true))
                    }
                }
            }
        }
    }

    private var description: String {
        switch store.settings.playbackQuality {
        case .original:
            "PLAYS IMPORTED FILES UNCHANGED. MAXIMUM FIDELITY, BUT HIGH-FRAME-RATE OR HIGH-BITRATE VIDEO MAY STUTTER ACROSS MULTIPLE DISPLAYS."
        case .performance:
            "CREATES LOCAL HEVC COPIES WITH APPLE'S HARDWARE VIDEO ENCODER AT UP TO 60 FPS. OPTIMIZATION PAUSES DURING PLAYBACK; ORIGINALS ARE PRESERVED AND NEVER UPLOADED."
        }
    }

    private var storageSummary: String {
        let actual = ByteCountFormatter.string(
            fromByteCount: store.optimizedStorageBytes,
            countStyle: .file
        )
        let estimate = ByteCountFormatter.string(
            fromByteCount: store.estimatedOptimizationBytes,
            countStyle: .file
        )
        return "LOCAL STORAGE: \(actual) USED / ABOUT \(estimate) WHEN COMPLETE. ORIGINALS REMAIN AVAILABLE."
    }
}
