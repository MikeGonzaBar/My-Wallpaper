import Foundation

struct WallpaperSettingsLoader {
    static let canonicalSettingsFilename = "app-settings-v1.json"
    static let backupSettingsFilename = "app-settings-v1.backup.json"

    static func loadInitialSettings(
        decoder: JSONDecoder,
        defaultsKey: String
    ) -> InitialSettingsLoad {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("My Wallpaper", isDirectory: true)
        let primaryFileURLs = [
            applicationSupport?.appendingPathComponent(canonicalSettingsFilename),
            applicationSupport?.appendingPathComponent(backupSettingsFilename)
        ].compactMap { $0 }
        var foundPersistedData = primaryFileURLs.contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
        var candidates = primaryFileURLs.compactMap { url in
            (try? Data(contentsOf: url)).map { ($0, true) }
        }
        if let defaultsData = UserDefaults.standard.data(forKey: defaultsKey) {
            foundPersistedData = true
            candidates.append((defaultsData, false))
        }
        if let legacySharedURL = applicationSupport?.appendingPathComponent("settings.json") {
            foundPersistedData = foundPersistedData
                || FileManager.default.fileExists(atPath: legacySharedURL.path)
            if let legacySharedData = try? Data(contentsOf: legacySharedURL) {
                candidates.append((legacySharedData, false))
            }
        }
        return decodeInitialSettings(
            candidates: candidates.map {
                SettingsDataCandidate(data: $0.0, requiresCanonicalEnvelope: $0.1)
            },
            foundPersistedData: foundPersistedData,
            decoder: decoder
        )
    }

    static func decodeInitialSettings(
        candidates: [SettingsDataCandidate],
        foundPersistedData: Bool,
        decoder: JSONDecoder = JSONDecoder()
    ) -> InitialSettingsLoad {
        guard !candidates.isEmpty else {
            return InitialSettingsLoad(
                settings: foundPersistedData ? nil : WallpaperSettings(),
                legacySettings: nil,
                hadUnrecoverableData: foundPersistedData
            )
        }

        for candidate in candidates {
            let data = candidate.data
            if candidate.requiresCanonicalEnvelope && !hasCanonicalSettingsEnvelope(data) {
                continue
            }
            if isLegacySingleVideoPayload(data) {
                if let legacy = try? decoder.decode(LegacyWallpaperSettings.self, from: data) {
                    return InitialSettingsLoad(
                        settings: nil,
                        legacySettings: legacy,
                        hadUnrecoverableData: false
                    )
                }
                continue
            }
            if let settings = try? decoder.decode(WallpaperSettings.self, from: data) {
                return InitialSettingsLoad(
                    settings: settings,
                    legacySettings: nil,
                    hadUnrecoverableData: false
                )
            }
            if let legacy = try? decoder.decode(LegacyWallpaperSettings.self, from: data) {
                return InitialSettingsLoad(
                    settings: nil,
                    legacySettings: legacy,
                    hadUnrecoverableData: false
                )
            }
        }
        return InitialSettingsLoad(
            settings: nil,
            legacySettings: nil,
            hadUnrecoverableData: true
        )
    }

    private static func isLegacySingleVideoPayload(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return false }
        return dictionary.keys.contains("videoPath")
    }

    private static func hasCanonicalSettingsEnvelope(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return false }
        return dictionary["schemaVersion"] is NSNumber
            && dictionary["configurationGeneration"] is String
    }
}

struct LegacyWallpaperSettings: Codable {
    let videoPath: String?
    let videoDisplayName: String?
    let idleMinutes: Int
    let isEnabled: Bool
    let isMuted: Bool
    let scaling: VideoScaling
}

struct SettingsDataCandidate {
    let data: Data
    let requiresCanonicalEnvelope: Bool
}

struct InitialSettingsLoad {
    let settings: WallpaperSettings?
    let legacySettings: LegacyWallpaperSettings?
    let hadUnrecoverableData: Bool

    var allowsDestructiveCleanup: Bool { !hadUnrecoverableData }
    var allowsAutomaticPersistence: Bool { !hadUnrecoverableData }
}
