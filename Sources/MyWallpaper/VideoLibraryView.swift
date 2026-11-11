import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoLibraryView: View {
    @ObservedObject var store: WallpaperStore
    @Binding var selectedVideoID: String?
    let onImport: () -> Void
    let addDestinationName: String?
    let onAddToDisplay: (ManagedVideo) -> Void

    @State private var searchText = ""
    @State private var filter = VideoLibraryFilter.all
    @State private var isConfirmingUnusedRemoval = false
    @State private var videoIDPendingRemoval: String?

    @State private var isChoosingReplacement = false
    @State private var replacementVideoID: String?
    @State private var replacementSelectionError: String?

    private var snapshot: VideoLibrarySnapshot {
        VideoLibrarySnapshot(settings: store.settings, search: searchText, filter: filter, selectedID: selectedVideoID)
    }

    var body: some View {
        let snapshot = self.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RetroPageHeader(
                    code: "SYS/02",
                    title: "VIDEO LIBRARY",
                    subtitle: "IMPORT ONCE. USE ON EVERY DISPLAY."
                ) {
                    RetroStatusBadge(
                        text: "\(snapshot.totalVideoCount) videos / \(snapshot.optimizedVideoCount) optimized",
                        active: !store.settings.videos.isEmpty
                    )
                }

                libraryToolbar

                HStack(alignment: .top, spacing: 16) {
                    libraryList(snapshot: snapshot)
                    detailsPanel(snapshot: snapshot)
                        .frame(width: 270)
                }

                Text("ORIGINALS: \(VideoLibraryStorage.formatted(snapshot.storage.originalBytes))  •  PERFORMANCE COPIES: \(VideoLibraryStorage.formatted(snapshot.storage.performanceBytes))")
                    .font(RetroFont.body(size: 9))
                HStack {
                    Text("\(snapshot.totalVideoCount) VIDEOS  •  \(snapshot.optimizedVideoCount) OPTIMIZED  •  \(VideoLibraryStorage.formatted(snapshot.storage.totalBytes).uppercased())")
                        .font(RetroFont.label(size: 9))
                    Spacer()
                    Button("REMOVE UNUSED…") {
                        isConfirmingUnusedRemoval = true
                    }
                    .buttonStyle(RetroButtonStyle())
                    .disabled(snapshot.unusedVideoCount == 0)
                }
            }
            .padding(24)
        }
        .background(RetroPalette.desktop)
        .fileImporter(isPresented: $isChoosingReplacement, allowedContentTypes: [.movie]) { result in
            guard let id = replacementVideoID else { return }
            replacementVideoID = nil
            switch result {
            case let .success(url): Task { await store.replaceLibraryVideo(id, from: url) }
            case let .failure(error):
                if (error as NSError).code != NSUserCancelledError {
                    replacementSelectionError = error.localizedDescription
                }
            }
        }
        .alert("COULD NOT SELECT A REPLACEMENT", isPresented: Binding(
            get: { replacementSelectionError != nil },
            set: { if !$0 { replacementSelectionError = nil } }
        )) {
            Button("OK", role: .cancel) { replacementSelectionError = nil }
        } message: { Text(replacementSelectionError ?? "") }
        .onAppear { reconcileSelection() }
        .onChange(of: store.settings.videos) { _, _ in reconcileSelection() }
        .onChange(of: searchText) { _, _ in reconcileSelection() }
        .onChange(of: filter) { _, _ in reconcileSelection() }
        .onChange(of: selectedVideoID) { _, requestedID in
            guard let requestedID,
                  store.settings.videos.contains(where: { $0.id == requestedID }),
                  !snapshot.visibleVideos.contains(where: { $0.id == requestedID }) else { return }
            searchText = ""
            filter = .all
        }
        .confirmationDialog(
            "REMOVE UNUSED VIDEOS?",
            isPresented: $isConfirmingUnusedRemoval,
            titleVisibility: .visible
        ) {
            Button("DELETE \(snapshot.unusedVideoCount) UNUSED VIDEO\(snapshot.unusedVideoCount == 1 ? "" : "S")", role: .destructive) {
                store.removeUnusedLibraryVideos()
            }
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text("This permanently deletes the unused managed originals and their performance copies. Estimated space reclaimed: \(VideoLibraryStorage.formatted(snapshot.storage.unusedBytes)).")
        }
        .confirmationDialog(
            "DELETE THIS VIDEO?",
            isPresented: Binding(
                get: { videoIDPendingRemoval != nil },
                set: { if !$0 { videoIDPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("DELETE VIDEO", role: .destructive) {
                if let videoIDPendingRemoval {
                    _ = store.removeVideoFromLibrary(videoIDPendingRemoval)
                }
                videoIDPendingRemoval = nil
            }
            Button("CANCEL", role: .cancel) { videoIDPendingRemoval = nil }
        } message: {
            let ids = Set([videoIDPendingRemoval].compactMap { $0 })
            let bytes = VideoLibraryStorage.reclaimableBytes(removing: ids, from: store.settings.videos)
            Text("This permanently deletes the managed original and its performance copy. Estimated space reclaimed: \(VideoLibraryStorage.formatted(bytes)).")
        }
    }

    private var libraryToolbar: some View {
        HStack(spacing: 12) {
            TextField("SEARCH LIBRARY", text: $searchText)
                .textFieldStyle(.plain)
                .font(RetroFont.body(size: 10))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }

            RetroChoiceBar(
                values: VideoLibraryFilter.allCases,
                selected: filter,
                accessibilityLabel: "Video library filter",
                title: { $0.title },
                onSelect: { filter = $0 }
            )
            .frame(width: 350)

            Button("IMPORT VIDEOS…", action: onImport)
                .buttonStyle(RetroButtonStyle(primary: true))
        }
    }

    private func libraryList(snapshot: VideoLibrarySnapshot) -> some View {
        RetroWindow(title: "SHARED VIDEO FILES") {
            if store.settings.videos.isEmpty {
                VStack(spacing: 14) {
                    Text("[ THE SHARED LIBRARY IS EMPTY ]")
                        .font(RetroFont.headline(size: 16))
                    Text("IMPORT A VIDEO ONCE, THEN ADD IT TO ANY DISPLAY.")
                        .font(RetroFont.body(size: 10))
                    Button("IMPORT VIDEOS…", action: onImport)
                        .buttonStyle(RetroButtonStyle(primary: true))
                }
                .frame(maxWidth: .infinity, minHeight: 360)
            } else if snapshot.visibleVideos.isEmpty {
                Text("[ NO VIDEOS MATCH THIS SEARCH OR FILTER ]")
                    .font(RetroFont.body(size: 10))
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(snapshot.visibleVideos.enumerated()), id: \.element.id) { index, video in
                        libraryRow(
                            video,
                            isSelected: snapshot.selectedVideo?.id == video.id,
                            usageCount: snapshot.usageCounts[video.id, default: 0],
                            isUnavailable: snapshot.unavailableVideoIDs.contains(video.id)
                        )
                        if index < snapshot.visibleVideos.count - 1 {
                            Rectangle().fill(RetroPalette.ink).frame(height: 1)
                        }
                    }
                }
                .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func libraryRow(
        _ video: ManagedVideo,
        isSelected: Bool,
        usageCount: Int,
        isUnavailable: Bool
    ) -> some View {
        Button {
            selectedVideoID = video.id
        } label: {
            HStack(spacing: 12) {
                VideoThumbnailView(videoURL: video.url, width: 112, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.displayName.uppercased())
                        .font(RetroFont.label(size: 10))
                        .lineLimit(1)
                    Text(VideoLibrarySnapshot.metadataText(for: video))
                        .font(RetroFont.body(size: 9))
                }
                Spacer()
                Text("\(usageCount) DISPLAY\(usageCount == 1 ? "" : "S")")
                    .font(RetroFont.body(size: 8))
                Text(statusText(for: video, isUnavailable: isUnavailable))
                    .font(RetroFont.label(size: 8))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .overlay { Rectangle().stroke(isSelected ? RetroPalette.paper : RetroPalette.ink, lineWidth: 1) }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 78)
            .foregroundStyle(isSelected ? RetroPalette.paper : RetroPalette.ink)
            .background(isSelected ? RetroPalette.ink : RetroPalette.paper)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detailsPanel(snapshot: VideoLibrarySnapshot) -> some View {
        RetroWindow(title: "DETAILS") {
            if let video = snapshot.selectedVideo {
                VideoLibraryDetailsView(
                    store: store, video: video,
                    usageCount: snapshot.usageCounts[video.id, default: 0],
                    addDestinationName: addDestinationName,
                    onAdd: { onAddToDisplay(video) },
                    onReplace: {
                        replacementVideoID = video.id
                        isChoosingReplacement = true
                    },
                    onRemove: { videoIDPendingRemoval = video.id }
                )
            } else {
                Text("SELECT A VIDEO TO VIEW ITS DETAILS.")
                    .font(RetroFont.body(size: 9))
                    .frame(minHeight: 360, alignment: .topLeading)
            }
        }
    }

    private func reconcileSelection() {
        let videos = snapshot.visibleVideos
        if !videos.contains(where: { $0.id == selectedVideoID }) {
            selectedVideoID = videos.first?.id
        }
    }

    private func statusText(for video: ManagedVideo, isUnavailable: Bool) -> String {
        if isUnavailable { return "MISSING / UNREADABLE" }
        if let state = store.optimization.state(for: video, profile: store.settings.optimizationProfile) {
            return state.title.uppercased()
        }
        if video.sourceMetadata?.isDemanding == true { return "HIGH LOAD" }
        return "ORIGINAL"
    }
}
