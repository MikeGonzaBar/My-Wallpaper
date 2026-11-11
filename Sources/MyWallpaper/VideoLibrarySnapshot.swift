import Foundation

enum VideoLibraryFilter: String, CaseIterable, Hashable {
    case all
    case highLoad
    case optimized
    case unavailable

    var title: String {
        switch self {
        case .all: "ALL"
        case .highLoad: "HIGH LOAD"
        case .optimized: "READY"
        case .unavailable: "MISSING"
        }
    }
}

struct VideoLibrarySnapshot {
    let visibleVideos: [ManagedVideo]
    let selectedVideo: ManagedVideo?
    let usageCounts: [String: Int]
    let optimizedVideoIDs: Set<String>
    let unavailableVideoIDs: Set<String>
    let storage: VideoLibraryStorage
    let totalVideoCount: Int
    let unusedVideoCount: Int

    var optimizedVideoCount: Int { optimizedVideoIDs.count }

    init(settings: WallpaperSettings, search: String, filter: VideoLibraryFilter, selectedID: String?) {
        let videos = settings.videos
        totalVideoCount = videos.count
        var counts = Dictionary(uniqueKeysWithValues: videos.map { ($0.id, 0) })
        for screen in settings.screens {
            for id in Set(screen.videoIDs + screen.stashedPlaylistVideoIDs) where counts[id] != nil {
                counts[id, default: 0] += 1
            }
        }
        usageCounts = counts
        unusedVideoCount = videos.filter { counts[$0.id, default: 0] == 0 }.count
        let readyIDs = Set(videos.filter {
            $0.optimizedProfile == settings.optimizationProfile
                && $0.optimizedPath.map(FileManager.default.isReadableFile(atPath:)) == true
        }.map(\.id))
        let missingIDs = Set(videos.filter { !Self.isReadableVideoFile($0.path) }.map(\.id))
        optimizedVideoIDs = readyIDs
        unavailableVideoIDs = missingIDs
        visibleVideos = videos.filter { video in
            let matchesSearch = search.isEmpty || video.displayName.localizedCaseInsensitiveContains(search)
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .highLoad: video.sourceMetadata?.isDemanding == true
            case .optimized: readyIDs.contains(video.id)
            case .unavailable: missingIDs.contains(video.id)
            }
            return matchesSearch && matchesFilter
        }
        selectedVideo = visibleVideos.first { $0.id == selectedID } ?? visibleVideos.first
        storage = VideoLibraryStorage(videos: videos, screens: settings.screens)
    }

    static func isReadableVideoFile(_ path: String) -> Bool {
        guard FileManager.default.isReadableFile(atPath: path),
              let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey]) else { return false }
        return values.isRegularFile == true
    }

    static func metadataText(for video: ManagedVideo) -> String {
        guard let metadata = video.sourceMetadata else { return "METADATA PENDING" }
        return "\(metadata.width) × \(metadata.height) • \(String(format: "%.2f", metadata.frameRate)) FPS"
    }
}
