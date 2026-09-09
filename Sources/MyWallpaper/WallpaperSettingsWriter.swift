import Foundation

struct WallpaperSettingsWriter {
    private let videoFiles: ManagedVideoFileStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        videoFiles: ManagedVideoFileStore,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.videoFiles = videoFiles
        self.encoder = encoder
        self.decoder = decoder
    }

    func persist(
        settings: WallpaperSettings,
        connectedDisplayIDs: [String]
    ) throws {
        let directory = try videoFiles.applicationSupportDirectory()
        let canonicalURL = directory.appendingPathComponent(
            WallpaperSettingsLoader.canonicalSettingsFilename
        )
        let backupURL = directory.appendingPathComponent(
            WallpaperSettingsLoader.backupSettingsFilename
        )
        let legacyURL = directory.appendingPathComponent("settings.json")
        let manifestURL = directory.appendingPathComponent("screensaver-manifest-v1.json")
        let fileURLs = [canonicalURL, backupURL, legacyURL, manifestURL]
        let snapshots = try fileURLs.map(snapshot)

        do {
            let canonicalData = try encoder.encode(settings)
            let legacyData = try encoder.encode(LegacySharedSettingsPayload(settings: settings))
            let manifest = ScreenSaverManifestBuilder.build(
                settings: settings,
                connectedDisplayIDs: connectedDisplayIDs
            )
            let manifestData = try manifest.map(encoder.encode)

            if let existingData = try? Data(contentsOf: canonicalURL),
               (try? decoder.decode(WallpaperSettings.self, from: existingData)) != nil {
                try writePrivate(existingData, to: backupURL)
            }
            try writePrivate(legacyData, to: legacyURL)

            if let manifestData {
                try writePrivate(manifestData, to: manifestURL)
            } else if FileManager.default.fileExists(atPath: manifestURL.path) {
                try FileManager.default.removeItem(at: manifestURL)
            }
            try writePrivate(canonicalData, to: canonicalURL)
        } catch {
            var rollbackIncomplete = false
            for snapshot in snapshots {
                do {
                    try restore(snapshot)
                } catch {
                    rollbackIncomplete = true
                }
            }
            throw WallpaperSettingsWriteError(
                underlying: error,
                rollbackIncomplete: rollbackIncomplete
            )
        }
    }

    private func snapshot(at url: URL) throws -> SettingsFileSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SettingsFileSnapshot(url: url, data: nil)
        }
        return SettingsFileSnapshot(url: url, data: try Data(contentsOf: url))
    }

    private func restore(_ snapshot: SettingsFileSnapshot) throws {
        if let data = snapshot.data {
            try writePrivate(data, to: snapshot.url)
        } else if FileManager.default.fileExists(atPath: snapshot.url.path) {
            try FileManager.default.removeItem(at: snapshot.url)
        }
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try videoFiles.ensurePrivateFilePermissions(at: url)
    }
}

private struct SettingsFileSnapshot {
    let url: URL
    let data: Data?
}

private struct LegacySharedSettingsPayload: Encodable {
    struct Screen: Encodable {
        let screenID: String
        let screenName: String
        let mode: String
        let videoIDs: [String]
        let startVideoID: String?
        let stashedPlaylistVideoIDs: [String]
    }

    let videos: [ManagedVideo]
    let screens: [Screen]
    let isMuted: Bool
    let scaling: String
    let playbackQuality: VideoPlaybackQuality
    let optimizationProfile: VideoOptimizationProfile

    init(settings: WallpaperSettings) {
        videos = settings.videos
        screens = settings.screens.map {
            Screen(
                screenID: $0.screenID,
                screenName: $0.screenName,
                mode: $0.mode.title,
                videoIDs: $0.videoIDs,
                startVideoID: $0.startVideoID,
                stashedPlaylistVideoIDs: $0.stashedPlaylistVideoIDs
            )
        }
        isMuted = settings.isMuted
        scaling = settings.scaling.title
        playbackQuality = settings.playbackQuality
        optimizationProfile = settings.optimizationProfile
    }
}

private struct WallpaperSettingsWriteError: LocalizedError {
    let underlying: Error
    let rollbackIncomplete: Bool

    var errorDescription: String? {
        underlying.localizedDescription + (rollbackIncomplete
            ? " Previous settings could not be fully restored."
            : "")
    }
}
