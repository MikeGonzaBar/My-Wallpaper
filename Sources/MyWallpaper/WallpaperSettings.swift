import Foundation

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

struct ManagedVideo: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let path: String

    var url: URL { URL(fileURLWithPath: path) }
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
