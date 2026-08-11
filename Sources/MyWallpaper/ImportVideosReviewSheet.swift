import SwiftUI

struct ImportVideosReviewSheet: View {
    @ObservedObject var store: WallpaperStore
    let candidates: [VideoImportCandidate]
    let destinationScreenID: String?
    let onChooseMore: () -> Void
    let onComplete: (String?) -> Void
    let onDismiss: () -> Void

    @State private var createPerformanceCopies: Bool

    init(
        store: WallpaperStore,
        candidates: [VideoImportCandidate],
        destinationScreenID: String?,
        onChooseMore: @escaping () -> Void,
        onComplete: @escaping (String?) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.candidates = candidates
        self.destinationScreenID = destinationScreenID
        self.onChooseMore = onChooseMore
        self.onComplete = onComplete
        self.onDismiss = onDismiss
        _createPerformanceCopies = State(
            initialValue: store.settings.playbackQuality == .performance
        )
    }

    private var importableCandidates: [VideoImportCandidate] {
        candidates.filter { !$0.isDuplicate }
    }

    private var performanceCopiesAreRequired: Bool {
        store.settings.playbackQuality == .performance
    }

    private var reusedLibraryVideoIDs: [String] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard case let .library(videoID) = candidate.duplicate,
                  seen.insert(videoID).inserted else { return nil }
            return videoID
        }
    }

    private var actionableVideoCount: Int {
        var identities = Set<String>()
        for candidate in candidates {
            switch candidate.duplicate {
            case let .library(videoID):
                identities.insert("library:\(videoID)")
            case let .selection(candidateID):
                identities.insert("candidate:\(candidateID.uuidString)")
            case nil:
                identities.insert("candidate:\(candidate.id.uuidString)")
            }
        }
        return identities.count
    }

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: "IMPORT NEW VIDEOS // SHARED LIBRARY")
            VStack(spacing: 16) {
                Text("COPY FILES INTO MY WALLPAPER. ORIGINALS ARE NEVER MODIFIED.")
                    .font(RetroFont.body(size: 10))

                HStack {
                    Text("\(candidates.count) FILE\(candidates.count == 1 ? "" : "S") READY TO REVIEW")
                        .font(RetroFont.label(size: 10))
                    Spacer()
                    Text("FILES STAY ON THIS MACINTOSH.")
                        .font(RetroFont.body(size: 9))
                        .foregroundStyle(RetroPalette.secondaryInk)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(candidates) { candidate in
                            candidateRow(candidate)
                            Rectangle().fill(RetroPalette.ink).frame(height: 1)
                        }
                    }
                }
                .frame(height: 300)
                .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }

                HStack(alignment: .top, spacing: 16) {
                    RetroWindow(title: "AFTER IMPORT") {
                        VStack(alignment: .leading, spacing: 8) {
                            RetroCheckbox(
                                title: "CREATE PERFORMANCE COPIES",
                                isOn: createPerformanceCopies,
                                action: { createPerformanceCopies.toggle() }
                            )
                            .disabled(performanceCopiesAreRequired || importableCandidates.isEmpty)
                            Text(store.settings.optimizationProfile.rawValue.uppercased())
                                .font(RetroFont.label(size: 9))
                            Text(performanceCopiesAreRequired
                                 ? "REQUIRED WHILE PERFORMANCE MODE IS ACTIVE."
                                 : "OPTIMIZATION RUNS AFTER IMPORT AND PAUSES DURING PLAYBACK.")
                                .font(RetroFont.body(size: 8))
                                .foregroundStyle(RetroPalette.secondaryInk)
                        }
                    }

                    RetroWindow(title: "SUMMARY") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(importableCandidates.count) NEW VIDEO\(importableCandidates.count == 1 ? "" : "S")")
                                .font(RetroFont.label(size: 10))
                            Text("\(reusedLibraryVideoIDs.count) ALREADY IN LIBRARY")
                                .font(RetroFont.body(size: 9))
                            Text(ByteCountFormatter.string(
                                fromByteCount: importableCandidates.reduce(0) { $0 + $1.fileSize },
                                countStyle: .file
                            ).uppercased() + " ORIGINALS")
                                .font(RetroFont.body(size: 9))
                            if let destinationScreenID {
                                Text("ADD TO \(store.configuration(for: destinationScreenID).screenName.uppercased())")
                                    .font(RetroFont.body(size: 9))
                            } else {
                                Text("ADD TO SHARED LIBRARY")
                                    .font(RetroFont.body(size: 9))
                            }
                        }
                    }
                }

                HStack {
                    Button("CANCEL", action: onDismiss)
                        .buttonStyle(RetroButtonStyle())
                    Spacer()
                    Button("ADD MORE FILES…") {
                        onChooseMore()
                    }
                    .buttonStyle(RetroButtonStyle())
                    Button(importButtonTitle) {
                        Task {
                            let imported = importableCandidates.isEmpty
                                ? []
                                : await store.importVideosToLibrary(candidates: candidates)
                            guard imported.count == importableCandidates.count else { return }
                            if !imported.isEmpty,
                               createPerformanceCopies,
                               store.settings.playbackQuality != .performance {
                                store.setPlaybackQuality(.performance)
                            }
                            let resolvedVideoIDs = VideoLibraryLogic.resolvedVideoIDs(
                                for: candidates,
                                importedVideos: imported
                            )
                            if let destinationScreenID {
                                store.assignVideos(resolvedVideoIDs, to: destinationScreenID)
                            }
                            onComplete(resolvedVideoIDs.first)
                        }
                    }
                    .buttonStyle(RetroButtonStyle(primary: true))
                    .disabled(actionableVideoCount == 0 || store.isImporting)
                }
            }
            .padding(20)
        }
        .frame(width: 880)
        .background(RetroPalette.paper)
        .foregroundStyle(RetroPalette.ink)
        .environment(\.font, RetroFont.body())
    }

    private var importButtonTitle: String {
        if store.isImporting { return "IMPORTING…" }
        if importableCandidates.isEmpty, destinationScreenID == nil {
            return "SHOW EXISTING VIDEO"
        }
        if destinationScreenID != nil {
            return "ADD \(actionableVideoCount) VIDEO\(actionableVideoCount == 1 ? "" : "S")"
        }
        return "IMPORT \(importableCandidates.count) VIDEO\(importableCandidates.count == 1 ? "" : "S")"
    }

    private func candidateRow(_ candidate: VideoImportCandidate) -> some View {
        HStack(spacing: 12) {
            VideoThumbnailView(videoURL: candidate.sourceURL, width: 104, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(candidate.displayName.uppercased())
                    .font(RetroFont.label(size: 10))
                    .lineLimit(1)
                Text(metadataText(for: candidate))
                    .font(RetroFont.body(size: 9))
                    .foregroundStyle(RetroPalette.secondaryInk)
            }
            Spacer()
            Text(ByteCountFormatter.string(
                fromByteCount: candidate.fileSize,
                countStyle: .file
            ).uppercased())
                .font(RetroFont.body(size: 9))
            Text(statusText(for: candidate))
                .font(RetroFont.label(size: 8))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 72)
        .opacity(candidate.isDuplicate ? 0.65 : 1)
    }

    private func metadataText(for candidate: VideoImportCandidate) -> String {
        guard let metadata = candidate.metadata else { return "METADATA UNAVAILABLE" }
        return "\(metadata.width) × \(metadata.height) • \(String(format: "%.2f", metadata.frameRate)) FPS"
    }

    private func statusText(for candidate: VideoImportCandidate) -> String {
        switch candidate.duplicate {
        case .library:
            "ALREADY IN LIBRARY"
        case .selection:
            "DUPLICATE SELECTION"
        case nil:
            candidate.metadata?.isDemanding == true ? "HIGH LOAD" : "READY"
        }
    }

}
