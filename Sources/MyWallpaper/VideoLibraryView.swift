import AppKit
import SwiftUI

struct VideoLibraryView: View {
    private static let fileSizeCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 4_096
        return cache
    }()

    @ObservedObject var store: WallpaperStore
    @Binding var selectedVideoID: String?
    let onImport: () -> Void
    let addDestinationName: String?
    let onAddToDisplay: (ManagedVideo) -> Void

    @State private var searchText = ""
    @State private var filter = VideoLibraryFilter.all
    @State private var isConfirmingUnusedRemoval = false
    @State private var videoIDPendingRemoval: String?

    private var filteredVideos: [ManagedVideo] {
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

    var body: some View {
        let snapshot = makeSnapshot()
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

                HStack {
                    Text("\(snapshot.totalVideoCount) VIDEOS  •  \(snapshot.optimizedVideoCount) OPTIMIZED  •  \(snapshot.librarySizeText)")
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
            Button("DELETE \(snapshot.unusedVideoCount) UNUSED VIDEO\(snapshot.unusedVideoCount == 1 ? "" : "S")", role: .destructive) {
                store.removeUnusedLibraryVideos()
            }
            Button("CANCEL", role: .cancel) {}
        } message: {
            Text("This permanently deletes the managed originals and their performance copies from this Mac.")
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
            Text("This permanently deletes the managed original and its performance copy from this Mac.")
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
            .frame(width: 300)

            Button("IMPORT VIDEOS…", action: onImport)
                .buttonStyle(RetroButtonStyle(primary: true))
        }
    }

    private func libraryList(snapshot: LibrarySnapshot) -> some View {
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
                            isOptimized: snapshot.optimizedVideoIDs.contains(video.id)
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
        isOptimized: Bool
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
                    Text(metadataText(for: video))
                        .font(RetroFont.body(size: 9))
                }
                Spacer()
                Text("\(usageCount) DISPLAY\(usageCount == 1 ? "" : "S")")
                    .font(RetroFont.body(size: 8))
                Text(statusText(for: video, isOptimized: isOptimized))
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

    private func detailsPanel(snapshot: LibrarySnapshot) -> some View {
        RetroWindow(title: "VIDEO DETAILS") {
            if let video = snapshot.selectedVideo {
                let usageCount = snapshot.usageCounts[video.id, default: 0]
                VStack(alignment: .leading, spacing: 14) {
                    VideoThumbnailView(videoURL: video.url, width: 228, height: 128)
                    Text(video.displayName.uppercased())
                        .font(RetroFont.label(size: 10))
                        .lineLimit(2)
                    Text(metadataText(for: video))
                        .font(RetroFont.body(size: 9))
                    RetroDivider()
                    Text("USED ON \(usageCount) DISPLAY\(usageCount == 1 ? "" : "S")")
                        .font(RetroFont.label(size: 9))
                    ForEach(displayNames(using: video.id), id: \.self) { name in
                        Text("■ \(name.uppercased())")
                            .font(RetroFont.body(size: 8))
                    }
                    if usageCount == 0 {
                        Text("NOT ASSIGNED TO A DISPLAY")
                            .font(RetroFont.body(size: 8))
                            .foregroundStyle(RetroPalette.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    Button(addDestinationName.map { "ADD TO \($0.uppercased())" } ?? "CONNECT A DISPLAY") {
                        onAddToDisplay(video)
                    }
                    .buttonStyle(RetroButtonStyle(primary: true, compact: true))
                    .disabled(addDestinationName == nil)
                    Button("REVEAL IN FINDER") {
                        NSWorkspace.shared.activateFileViewerSelecting([video.url])
                    }
                    .buttonStyle(RetroButtonStyle(compact: true))
                    if usageCount == 0 {
                        Button("REMOVE FROM LIBRARY…", role: .destructive) {
                            videoIDPendingRemoval = video.id
                        }
                        .buttonStyle(RetroButtonStyle(compact: true))
                    }
                }
            } else {
                Text("SELECT A VIDEO TO VIEW ITS DETAILS.")
                    .font(RetroFont.body(size: 9))
                    .frame(minHeight: 360, alignment: .topLeading)
            }
        }
    }

    private func reconcileSelection() {
        let videos = filteredVideos
        if !videos.contains(where: { $0.id == selectedVideoID }) {
            selectedVideoID = videos.first?.id
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

    private func statusText(for video: ManagedVideo, isOptimized: Bool) -> String {
        if isOptimized { return "OPTIMIZED" }
        if video.sourceMetadata?.isDemanding == true { return "HIGH LOAD" }
        return "ORIGINAL"
    }

    private func makeSnapshot() -> LibrarySnapshot {
        let videos = store.settings.videos
        var usageCounts = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, 0) })
        for screen in store.settings.screens {
            let assignedIDs = Set(screen.videoIDs).union(screen.stashedPlaylistVideoIDs)
            for videoID in assignedIDs where usageCounts[videoID] != nil {
                usageCounts[videoID, default: 0] += 1
            }
        }

        var optimizedVideoIDs = Set<String>()
        var storageBytes: Int64 = 0
        for video in videos {
            storageBytes += Self.fileSize(atPath: video.path)
            if let optimizedPath = video.optimizedPath {
                storageBytes += Self.fileSize(atPath: optimizedPath)
            }
            guard video.optimizedProfile == store.settings.optimizationProfile,
                  let optimizedPath = video.optimizedPath,
                  FileManager.default.isReadableFile(atPath: optimizedPath) else { continue }
            optimizedVideoIDs.insert(video.id)
        }

        let visibleVideos = videos.filter { video in
            let matchesSearch = searchText.isEmpty
                || video.displayName.localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .highLoad: video.sourceMetadata?.isDemanding == true
            case .optimized: optimizedVideoIDs.contains(video.id)
            }
            return matchesSearch && matchesFilter
        }
        let selectedVideo = visibleVideos.first { $0.id == selectedVideoID }
            ?? visibleVideos.first
        return LibrarySnapshot(
            visibleVideos: visibleVideos,
            selectedVideo: selectedVideo,
            usageCounts: usageCounts,
            optimizedVideoIDs: optimizedVideoIDs,
            totalVideoCount: videos.count,
            optimizedVideoCount: optimizedVideoIDs.count,
            unusedVideoCount: videos.reduce(into: 0) { count, video in
                if usageCounts[video.id, default: 0] == 0 { count += 1 }
            },
            librarySizeText: ByteCountFormatter.string(
                fromByteCount: storageBytes,
                countStyle: .file
            ).uppercased()
        )
    }

    private static func fileSize(atPath path: String) -> Int64 {
        if let cached = fileSizeCache.object(forKey: path as NSString) {
            return cached.int64Value
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        fileSizeCache.setObject(NSNumber(value: size), forKey: path as NSString)
        return size
    }
}

private struct LibrarySnapshot {
    let visibleVideos: [ManagedVideo]
    let selectedVideo: ManagedVideo?
    let usageCounts: [String: Int]
    let optimizedVideoIDs: Set<String>
    let totalVideoCount: Int
    let optimizedVideoCount: Int
    let unusedVideoCount: Int
    let librarySizeText: String
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
