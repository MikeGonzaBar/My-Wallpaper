import XCTest
@testable import MyWallpaper

final class WallpaperSettingsWriterTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var videoFiles: ManagedVideoFileStore!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        videoFiles = ManagedVideoFileStore(rootDirectory: temporaryDirectory)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        videoFiles = nil
        temporaryDirectory = nil
    }

    func testPersistWritesPrivateCanonicalLegacyAndManifestFiles() throws {
        let settings = try makePlayableSettings()

        try WallpaperSettingsWriter(videoFiles: videoFiles).persist(
            settings: settings,
            connectedDisplayIDs: ["display"]
        )

        let canonical = temporaryDirectory.appendingPathComponent(
            WallpaperSettingsLoader.canonicalSettingsFilename
        )
        let legacy = temporaryDirectory.appendingPathComponent("settings.json")
        let manifest = temporaryDirectory.appendingPathComponent("screensaver-manifest-v1.json")
        XCTAssertEqual(try JSONDecoder().decode(WallpaperSettings.self, from: Data(contentsOf: canonical)), settings)
        XCTAssertNoThrow(try Data(contentsOf: legacy))
        XCTAssertNoThrow(try Data(contentsOf: manifest))
        XCTAssertEqual(permissions(at: canonical), 0o600)
        XCTAssertEqual(permissions(at: legacy), 0o600)
        XCTAssertEqual(permissions(at: manifest), 0o600)
    }

    func testSecondPersistBacksUpPreviousCanonicalSettings() throws {
        let writer = WallpaperSettingsWriter(videoFiles: videoFiles)
        let original = try makePlayableSettings(isMuted: true)
        let replacement = try makePlayableSettings(isMuted: false)

        try writer.persist(settings: original, connectedDisplayIDs: ["display"])
        try writer.persist(settings: replacement, connectedDisplayIDs: ["display"])

        let backup = temporaryDirectory.appendingPathComponent(
            WallpaperSettingsLoader.backupSettingsFilename
        )
        let decoded = try JSONDecoder().decode(WallpaperSettings.self, from: Data(contentsOf: backup))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(permissions(at: backup), 0o600)
    }

    private func makePlayableSettings(isMuted: Bool = true) throws -> WallpaperSettings {
        let directory = try videoFiles.managedVideosDirectory()
        let videoURL = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        try Data("video".utf8).write(to: videoURL)
        let video = ManagedVideo(id: "video", displayName: "Video", path: videoURL.path)
        let screen = ScreenConfiguration(
            screenID: "display",
            screenName: "Display",
            videoIDs: [video.id],
            startVideoID: video.id
        )
        return WallpaperSettings(videos: [video], screens: [screen], isMuted: isMuted)
    }

    private func permissions(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }
}
