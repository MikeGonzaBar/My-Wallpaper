import Foundation

enum ScreenSaverScaling: String, Codable {
    case fill
    case fit

    init(_ scaling: VideoScaling) {
        self = scaling == .fill ? .fill : .fit
    }
}

struct ScreenSaverDisplayManifest: Codable, Equatable {
    let displayID: String
    let orderedVideoPaths: [String]
}

struct ScreenSaverManifest: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let configurationGeneration: UUID
    let isMuted: Bool
    let scaling: ScreenSaverScaling
    let fallbackDisplayID: String
    let displays: [ScreenSaverDisplayManifest]
}

enum ScreenSaverManifestBuilder {
    static func build(
        settings: WallpaperSettings,
        connectedDisplayIDs: [String],
        isReadableFile: (String) -> Bool = {
            FileManager.default.isReadableFile(atPath: $0)
        }
    ) -> ScreenSaverManifest? {
        var videosByID: [String: ManagedVideo] = [:]
        settings.videos.forEach { videosByID[$0.id] = $0 }
        let displays = settings.screens.compactMap { configuration -> ScreenSaverDisplayManifest? in
            let playable = configuration.videoIDs.compactMap { videoID -> (ManagedVideo, String)? in
                guard let video = videosByID[videoID] else { return nil }
                let playbackPath = video.playbackPath(
                    quality: settings.playbackQuality,
                    profile: settings.optimizationProfile,
                    isReadableFile: isReadableFile
                )
                guard isReadableFile(playbackPath) else { return nil }
                return (video, playbackPath)
            }
            guard !playable.isEmpty else { return nil }

            let orderedVideos: [(ManagedVideo, String)]
            if configuration.mode == .single {
                let selected = playable.first { $0.0.id == configuration.startVideoID } ?? playable[0]
                orderedVideos = [selected]
            } else {
                let startIndex = playable.firstIndex { $0.0.id == configuration.startVideoID } ?? 0
                orderedVideos = Array(playable[startIndex...]) + Array(playable[..<startIndex])
            }

            return ScreenSaverDisplayManifest(
                displayID: configuration.screenID,
                orderedVideoPaths: orderedVideos.map(\.1)
            )
        }

        guard !displays.isEmpty else { return nil }
        let connectedIDs = Set(connectedDisplayIDs)
        let fallback = displays.first { connectedIDs.contains($0.displayID) } ?? displays[0]

        return ScreenSaverManifest(
            schemaVersion: ScreenSaverManifest.currentSchemaVersion,
            configurationGeneration: settings.configurationGeneration,
            isMuted: settings.isMuted,
            scaling: ScreenSaverScaling(settings.scaling),
            fallbackDisplayID: fallback.displayID,
            displays: displays
        )
    }
}
