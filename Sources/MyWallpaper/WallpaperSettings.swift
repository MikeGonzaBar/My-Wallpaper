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
    case fill
    case fit

    var id: String { rawValue }
    var title: String {
        switch self {
        case .fill: "Fill screen"
        case .fit: "Fit to screen"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.fill.rawValue, "Fill screen": self = .fill
        case Self.fit.rawValue, "Fit to screen": self = .fit
        default: throw StableEnumDecodingError.unknownValue(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum PlaybackMode: String, CaseIterable, Codable, Identifiable {
    case single
    case playlist

    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: "Single video"
        case .playlist: "Playlist"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.single.rawValue, "Single video": self = .single
        case Self.playlist.rawValue, "Playlist": self = .playlist
        default: throw StableEnumDecodingError.unknownValue(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum VideoPlaybackQuality: String, CaseIterable, Codable, Identifiable {
    case original
    case performance

    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: "Original quality"
        case .performance: "Performance mode"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.original.rawValue, "Original quality": self = .original
        case Self.performance.rawValue, "Performance mode": self = .performance
        default: throw StableEnumDecodingError.unknownValue(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum VideoOptimizationProfile: String, CaseIterable, Codable, Identifiable {
    case efficient
    case maximum

    var id: String { rawValue }
    var title: String {
        switch self {
        case .efficient: "1440p / 60 FPS"
        case .maximum: "4K / 60 FPS"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case Self.efficient.rawValue, "1440p / 60 FPS": self = .efficient
        case Self.maximum.rawValue, "4K / 60 FPS": self = .maximum
        default: throw StableEnumDecodingError.unknownValue(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

private enum StableEnumDecodingError: LocalizedError {
    case unknownValue(String)

    var errorDescription: String? {
        switch self {
        case let .unknownValue(value):
            "Unknown persisted settings value: \(value)"
        }
    }
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
    var contentFingerprint: String?

    init(
        id: String,
        displayName: String,
        path: String,
        optimizedPath: String? = nil,
        optimizedProfile: VideoOptimizationProfile? = nil,
        sourceMetadata: VideoTechnicalMetadata? = nil,
        contentFingerprint: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.path = path
        self.optimizedPath = optimizedPath
        self.optimizedProfile = optimizedProfile
        self.sourceMetadata = sourceMetadata
        self.contentFingerprint = contentFingerprint
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
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var configurationGeneration = UUID()
    var videos: [ManagedVideo] = []
    var screens: [ScreenConfiguration] = []
    var isMuted = true
    var scaling = VideoScaling.fill
    var playbackQuality = VideoPlaybackQuality.original
    var optimizationProfile = VideoOptimizationProfile.efficient

    init(
        schemaVersion: Int = currentSchemaVersion,
        configurationGeneration: UUID = UUID(),
        videos: [ManagedVideo] = [],
        screens: [ScreenConfiguration] = [],
        isMuted: Bool = true,
        scaling: VideoScaling = .fill,
        playbackQuality: VideoPlaybackQuality = .original,
        optimizationProfile: VideoOptimizationProfile = .efficient
    ) {
        self.schemaVersion = schemaVersion
        self.configurationGeneration = configurationGeneration
        self.videos = videos
        self.screens = screens
        self.isMuted = isMuted
        self.scaling = scaling
        self.playbackQuality = playbackQuality
        self.optimizationProfile = optimizationProfile
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, configurationGeneration
        case videos, screens, isMuted, scaling, playbackQuality, optimizationProfile
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw WallpaperSettingsDecodingError.unsupportedSchemaVersion(schemaVersion)
        }
        configurationGeneration = try values.decodeIfPresent(
            UUID.self,
            forKey: .configurationGeneration
        ) ?? UUID()
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

    func repaired() -> WallpaperSettings {
        var result = self
        result.schemaVersion = Self.currentSchemaVersion

        var seenVideoIDs = Set<String>()
        result.videos = videos.filter { !$0.id.isEmpty && seenVideoIDs.insert($0.id).inserted }
        for index in result.videos.indices {
            let hasOptimizedPath = result.videos[index].optimizedPath != nil
            let hasOptimizedProfile = result.videos[index].optimizedProfile != nil
            if hasOptimizedPath != hasOptimizedProfile {
                result.videos[index].optimizedPath = nil
                result.videos[index].optimizedProfile = nil
            }
        }

        let validVideoIDs = Set(result.videos.map(\.id))
        var seenScreenIDs = Set<String>()
        result.screens = screens.compactMap { screen in
            guard !screen.screenID.isEmpty,
                  seenScreenIDs.insert(screen.screenID).inserted else { return nil }
            var repaired = screen
            repaired.videoIDs = Self.validUniqueIDs(screen.videoIDs, in: validVideoIDs)
            repaired.stashedPlaylistVideoIDs = Self.validUniqueIDs(
                screen.stashedPlaylistVideoIDs,
                in: validVideoIDs
            )
            if !repaired.videoIDs.contains(repaired.startVideoID ?? "") {
                repaired.startVideoID = repaired.videoIDs.first
            }
            return repaired
        }
        return result
    }

    private static func validUniqueIDs(_ ids: [String], in validIDs: Set<String>) -> [String] {
        var seen = Set<String>()
        return ids.filter { validIDs.contains($0) && seen.insert($0).inserted }
    }
}

enum WallpaperSettingsMigration {
    static func assigningLegacyVideoIfNeeded(
        in settings: WallpaperSettings,
        displays: [DisplayInfo],
        decodedFromLegacyFormat: Bool
    ) -> WallpaperSettings {
        guard decodedFromLegacyFormat,
              settings.screens.isEmpty,
              let video = settings.videos.first else { return settings }
        var migrated = settings
        migrated.screens = displays.map {
            ScreenConfiguration(
                screenID: $0.id,
                screenName: $0.name,
                videoIDs: [video.id],
                startVideoID: video.id
            )
        }
        return migrated
    }
}

private enum WallpaperSettingsDecodingError: LocalizedError {
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "Settings schema version \(version) is newer than this app supports."
        }
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
