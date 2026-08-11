import AppKit
import SwiftUI

struct VideoLibraryView: View {
    @ObservedObject var store: WallpaperStore
    @Binding var selectedVideoID: String?
    let onImport: () -> Void
    let onAddToDisplay: (ManagedVideo) -> Void

    @State private var searchText = ""
    @State private var filter = VideoLibraryFilter.all
    @State private var isConfirmingUnusedRemoval = false

    private var visibleVideos: [ManagedVideo] {
        store.settings.videos.filter { video in
            let matchesSearch = searchText.isEmpty
                || video.displayName.localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .highLoad: video.sourceMetadata?.isDemanding == true
            case .optimized:
                video.optimizedProfile == store.settings.optimizationProfile
                    && video.optimizedPath.map(FileManager.default.isReadableFile(atPath:)) == true
            }
            return matchesSearch && matchesFilter
        }
    }

    private var selectedVideo: ManagedVideo? {
        visibleVideos.first { $0.id == selectedVideoID }
            ?? visibleVideos.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RetroPageHeader(
                    code: "SYS/02",
                    title: "VIDEO LIBRARY",
                    subtitle: "IMPORT ONCE. USE ON EVERY DISPLAY."
                ) {
                    RetroStatusBadge(
                        text: "\(store.settings.videos.count) videos / \(store.optimizedVideoCount) optimized",
                        active: !store.settings.videos.isEmpty
                    )
                }

                libraryToolbar

                HStack(alignment: .top, spacing: 16) {
                    libraryList
                    detailsPanel
                        .frame(width: 270)
                }

                HStack {
                    Text("\(store.settings.videos.count) VIDEOS  •  \(store.optimizedVideoCount) OPTIMIZED  •  \(librarySizeText)")
                        .font(RetroFont.label(size: 9))
                    Spacer()
                    Button("REMOVE UNUSED…") {
                        isConfirmingUnusedRemoval = true
                    }
                    .buttonStyle(RetroButtonStyle())
                    .disabled(store.unusedVideoCount == 0)
                }
            }
            .padding(24)
        }
        .background(RetroPalette.desktop)
        .onAppear { reconcileSelection() }
        .onChange(of: store.settings.videos) { _, _ in reconcileSelection() }
        .onChange(of: searchText) { _, _ in reconcileSelection() }
        .onChange(of: filter) { _, _ in reconcileSelection() }
        .onChange(of: selectedVideoID) { _, requestedID in
            guard let requestedID,
                  store.settings.videos.contains(where: { $0.id == requestedID }) else { return }
            searchText = ""
            filter = .all
        }
        .confirmationDialog(
            "REMOVE UNUSED VIDEOS?",
            isPresented: $isConfirmingUnusedRemoval,
            titleVisibility: .visible
        ) {
            Button("DELETE \(store.unusedVideoCount) UNUSED VIDEO\(store.unusedVideoCount == 1 ? "" : "S")", role: .destructive) {
                store.removeUnusedLibraryVideos()
            }
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text("This permanently deletes the managed originals and their performance copies from this Mac.")
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
                title: { $0.title },
                onSelect: { filter = $0 }
            )
            .frame(width: 300)

            Button("IMPORT VIDEOS…", action: onImport)
                .buttonStyle(RetroButtonStyle(primary: true))
        }
    }

    private var libraryList: some View {
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
            } else if visibleVideos.isEmpty {
                Text("[ NO VIDEOS MATCH THIS SEARCH OR FILTER ]")
                    .font(RetroFont.body(size: 10))
                    .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleVideos) { video in
                        libraryRow(video)
                        if video.id != visibleVideos.last?.id {
                            Rectangle().fill(RetroPalette.ink).frame(height: 1)
                        }
                    }
                }
                .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func libraryRow(_ video: ManagedVideo) -> some View {
        let isSelected = selectedVideo?.id == video.id
        return Button {
            selectedVideoID = video.id
        } label: {
            HStack(spacing: 12) {
                VideoThumbnailView(videoURL: video.url, width: 112, height: 64)
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.displayName.uppercased())
                        .font(RetroFont.label(size: 10))
                        .lineLimit(1)
                    Text(metadataText(for: video))
                        .font(RetroFont.body(size: 9))
                }
                Spacer()
                Text("\(store.usageCount(for: video.id)) DISPLAY\(store.usageCount(for: video.id) == 1 ? "" : "S")")
                    .font(RetroFont.body(size: 8))
                Text(statusText(for: video))
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

    private var detailsPanel: some View {
        RetroWindow(title: "VIDEO DETAILS") {
            if let video = selectedVideo {
                VStack(alignment: .leading, spacing: 14) {
                    VideoThumbnailView(videoURL: video.url, width: 228, height: 128)
                    Text(video.displayName.uppercased())
                        .font(RetroFont.label(size: 10))
                        .lineLimit(2)
                    Text(metadataText(for: video))
                        .font(RetroFont.body(size: 9))
                    RetroDivider()
                    Text("USED ON \(store.usageCount(for: video.id)) DISPLAY\(store.usageCount(for: video.id) == 1 ? "" : "S")")
                        .font(RetroFont.label(size: 9))
                    ForEach(displayNames(using: video.id), id: \.self) { name in
                        Text("■ \(name.uppercased())")
                            .font(RetroFont.body(size: 8))
                    }
                    if store.usageCount(for: video.id) == 0 {
                        Text("NOT ASSIGNED TO A DISPLAY")
                            .font(RetroFont.body(size: 8))
                            .foregroundStyle(RetroPalette.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    Button("ADD TO SELECTED DISPLAY…") {
                        onAddToDisplay(video)
                    }
                    .buttonStyle(RetroButtonStyle(primary: true, compact: true))
                    Button("REVEAL IN FINDER") {
                        NSWorkspace.shared.activateFileViewerSelecting([video.url])
                    }
                    .buttonStyle(RetroButtonStyle(compact: true))
                }
            } else {
                Text("SELECT A VIDEO TO VIEW ITS DETAILS.")
                    .font(RetroFont.body(size: 9))
                    .frame(minHeight: 360, alignment: .topLeading)
            }
        }
    }

    private var librarySizeText: String {
        let total = store.settings.videos.reduce(Int64(0)) { result, video in
            let attributes = try? FileManager.default.attributesOfItem(atPath: video.path)
            return result + ((attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        } + store.optimizedStorageBytes
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file).uppercased()
    }

    private func reconcileSelection() {
        if !visibleVideos.contains(where: { $0.id == selectedVideoID }) {
            selectedVideoID = visibleVideos.first?.id
        }
    }

    private func displayNames(using videoID: String) -> [String] {
        store.settings.screens.filter {
            $0.videoIDs.contains(videoID) || $0.stashedPlaylistVideoIDs.contains(videoID)
        }.map(\.screenName)
    }

    private func metadataText(for video: ManagedVideo) -> String {
        guard let metadata = video.sourceMetadata else { return "METADATA PENDING" }
        return "\(metadata.width) × \(metadata.height) • \(String(format: "%.2f", metadata.frameRate)) FPS"
    }

    private func statusText(for video: ManagedVideo) -> String {
        if video.optimizedProfile == store.settings.optimizationProfile,
           let path = video.optimizedPath,
           FileManager.default.isReadableFile(atPath: path) {
            return "OPTIMIZED"
        }
        if video.sourceMetadata?.isDemanding == true { return "HIGH LOAD" }
        return "ORIGINAL"
    }
}

private enum VideoLibraryFilter: String, CaseIterable, Hashable {
    case all
    case highLoad
    case optimized

    var title: String {
        switch self {
        case .all: "ALL"
        case .highLoad: "HIGH LOAD"
        case .optimized: "OPTIMIZED"
        }
    }
}
