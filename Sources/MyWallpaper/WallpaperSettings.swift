import Foundation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum VideoScaling: String, CaseIterable, Codable, Identifiable {
    case fill = "Fill screen"
    case fit = "Fit to screen"

    var id: String { rawValue }
}

enum PlaybackMode: String, CaseIterable, Codable, Identifiable {
    case single = "Single video"
    case playlist = "Playlist"

    var id: String { rawValue }
}

enum VideoPlaybackQuality: String, CaseIterable, Codable, Identifiable {
    case original = "Original quality"
    case performance = "Performance mode"

    var id: String { rawValue }
}

enum VideoOptimizationProfile: String, CaseIterable, Codable, Identifiable {
    case efficient = "1440p / 60 FPS"
    case maximum = "4K / 60 FPS"

    var id: String { rawValue }
}

struct VideoTechnicalMetadata: Codable, Equatable {
    let width: Int
    let height: Int
    let frameRate: Double
    let estimatedBitRate: Double
    let durationSeconds: Double?

    init(
        width: Int,
        height: Int,
        frameRate: Double,
        estimatedBitRate: Double,
        durationSeconds: Double? = nil
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.estimatedBitRate = estimatedBitRate
        self.durationSeconds = durationSeconds
    }

    var isDemanding: Bool {
        frameRate > 60.5 || estimatedBitRate > 60_000_000 ||
            Double(width) * Double(height) * max(frameRate, 1) > Double(3840 * 2160 * 60)
    }
}

struct ManagedVideo: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let path: String
    var optimizedPath: String?
    var optimizedProfile: VideoOptimizationProfile?
    var sourceMetadata: VideoTechnicalMetadata?

    init(
        id: String,
        displayName: String,
        path: String,
        optimizedPath: String? = nil,
        optimizedProfile: VideoOptimizationProfile? = nil,
        sourceMetadata: VideoTechnicalMetadata? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.optimizedPath = optimizedPath
        self.optimizedProfile = optimizedProfile
        self.sourceMetadata = sourceMetadata
    }

    var url: URL { URL(fileURLWithPath: path) }

    func playbackPath(
        quality: VideoPlaybackQuality,
        profile: VideoOptimizationProfile,
        isReadableFile: (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) }
    ) -> String {
        if quality == .performance,
           optimizedProfile == profile,
           let optimizedPath,
           isReadableFile(optimizedPath) {
            return optimizedPath
        }
        return path
    }
}

struct DisplayInfo: Equatable, Identifiable {
    let id: String
    let name: String
}

struct ScreenConfiguration: Codable, Equatable, Identifiable {
    var screenID: String
    var screenName: String
    var mode = PlaybackMode.single
    var videoIDs: [String] = []
    var startVideoID: String?
    var stashedPlaylistVideoIDs: [String] = []

    var id: String { screenID }

    mutating func changeMode(to newMode: PlaybackMode) {
        guard mode != newMode else { return }
        if newMode == .single, videoIDs.count > 1 {
            stashedPlaylistVideoIDs = videoIDs
            let retainedID = startVideoID ?? videoIDs[0]
            videoIDs = [retainedID]
            startVideoID = retainedID
        } else if newMode == .playlist, !stashedPlaylistVideoIDs.isEmpty {
            let currentIDs = videoIDs
            videoIDs = stashedPlaylistVideoIDs
            for id in currentIDs where !videoIDs.contains(id) {
                videoIDs.append(id)
            }
            stashedPlaylistVideoIDs = []
        }
        mode = newMode
    }
}

struct WallpaperSettings: Codable, Equatable {
    var videos: [ManagedVideo] = []
    var screens: [ScreenConfiguration] = []
    var isMuted = true
    var scaling = VideoScaling.fill
    var playbackQuality = VideoPlaybackQuality.original
    var optimizationProfile = VideoOptimizationProfile.efficient

    init(
        videos: [ManagedVideo] = [],
        screens: [ScreenConfiguration] = [],
        isMuted: Bool = true,
        scaling: VideoScaling = .fill,
        playbackQuality: VideoPlaybackQuality = .original,
        optimizationProfile: VideoOptimizationProfile = .efficient
    ) {
        self.videos = videos
        self.screens = screens
        self.isMuted = isMuted
        self.scaling = scaling
        self.playbackQuality = playbackQuality
        self.optimizationProfile = optimizationProfile
    }

    private enum CodingKeys: String, CodingKey {
        case videos, screens, isMuted, scaling, playbackQuality, optimizationProfile
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        videos = try values.decodeIfPresent([ManagedVideo].self, forKey: .videos) ?? []
        screens = try values.decodeIfPresent([ScreenConfiguration].self, forKey: .screens) ?? []
        isMuted = try values.decodeIfPresent(Bool.self, forKey: .isMuted) ?? true
        scaling = try values.decodeIfPresent(VideoScaling.self, forKey: .scaling) ?? .fill
        playbackQuality = try values.decodeIfPresent(
            VideoPlaybackQuality.self,
            forKey: .playbackQuality
        ) ?? .original
        optimizationProfile = try values.decodeIfPresent(
            VideoOptimizationProfile.self,
            forKey: .optimizationProfile
        ) ?? .efficient
    }
}

struct ScreenPlaybackPlan: Equatable {
    let screenID: String
    let videoURLs: [URL]
    let startIndex: Int

    var orderedVideoURLs: [URL] {
        guard videoURLs.indices.contains(startIndex), startIndex > 0 else {
            return videoURLs
        }
        return Array(videoURLs[startIndex...]) + Array(videoURLs[..<startIndex])
    }
}
