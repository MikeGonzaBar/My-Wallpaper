import XCTest
@testable import MyWallpaper

final class ScreenSaverManifestTests: XCTestCase {
    func testSingleVideoUsesSelectedStartingVideo() throws {
        let settings = makeSettings(
            mode: .single,
            videoIDs: ["one", "two"],
            startVideoID: "two"
        )

        let manifest = try XCTUnwrap(build(settings))

        XCTAssertEqual(manifest.displays[0].orderedVideoPaths, ["/two.mp4"])
        XCTAssertEqual(manifest.scaling, .fill)
    }

    func testPlaylistRotatesFromSelectedStartingVideo() throws {
        let settings = makeSettings(
            mode: .playlist,
            videoIDs: ["one", "two", "three"],
            startVideoID: "two"
        )

        let manifest = try XCTUnwrap(build(settings))

        XCTAssertEqual(
            manifest.displays[0].orderedVideoPaths,
            ["/two.mp4", "/three.mp4", "/one.mp4"]
        )
    }

    func testMissingVideosAreOmittedAndInvalidStartFallsBackToFirst() throws {
        let settings = makeSettings(
            mode: .playlist,
            videoIDs: ["one", "missing", "three"],
            startVideoID: "missing"
        )

        let manifest = try XCTUnwrap(ScreenSaverManifestBuilder.build(
            settings: settings,
            connectedDisplayIDs: ["display"],
            isReadableFile: { $0 != "/missing.mp4" }
        ))

        XCTAssertEqual(manifest.displays[0].orderedVideoPaths, ["/one.mp4", "/three.mp4"])
    }

    func testFallbackPrefersPlayableConnectedDisplay() throws {
        let disconnected = makeConfiguration(id: "disconnected", videoID: "one")
        let connected = makeConfiguration(id: "connected", videoID: "two")
        let settings = WallpaperSettings(
            videos: makeVideos(["one", "two"]),
            screens: [disconnected, connected]
        )

        let manifest = try XCTUnwrap(ScreenSaverManifestBuilder.build(
            settings: settings,
            connectedDisplayIDs: ["connected"],
            isReadableFile: { _ in true }
        ))

        XCTAssertEqual(manifest.fallbackDisplayID, "connected")
        XCTAssertEqual(manifest.displays.map(\.displayID), ["disconnected", "connected"])
    }

    func testFallbackUsesFirstSavedPlayableDisplayWhenNoneAreConnected() throws {
        let settings = makeSettings(
            mode: .single,
            videoIDs: ["one"],
            startVideoID: "one"
        )

        let manifest = try XCTUnwrap(ScreenSaverManifestBuilder.build(
            settings: settings,
            connectedDisplayIDs: ["new-display"],
            isReadableFile: { _ in true }
        ))

        XCTAssertEqual(manifest.fallbackDisplayID, "display")
    }

    func testNoReadableVideosProducesNoManifest() {
        let settings = makeSettings(
            mode: .single,
            videoIDs: ["one"],
            startVideoID: "one"
        )

        XCTAssertNil(ScreenSaverManifestBuilder.build(
            settings: settings,
            connectedDisplayIDs: ["display"],
            isReadableFile: { _ in false }
        ))
    }

    func testManifestRoundTripPreservesSchemaAndPlayback() throws {
        var settings = makeSettings(
            mode: .playlist,
            videoIDs: ["one", "two"],
            startVideoID: "two"
        )
        settings.isMuted = false
        settings.scaling = .fit
        let manifest = try XCTUnwrap(build(settings))

        let decoded = try JSONDecoder().decode(
            ScreenSaverManifest.self,
            from: JSONEncoder().encode(manifest)
        )

        XCTAssertEqual(decoded, manifest)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.scaling, .fit)
        XCTAssertFalse(decoded.isMuted)
    }

    func testPerformanceModeUsesMatchingReadableOptimizedCopy() throws {
        var settings = makeSettings(mode: .single, videoIDs: ["one"], startVideoID: "one")
        settings.playbackQuality = .performance
        settings.optimizationProfile = .efficient
        settings.videos[0].optimizedPath = "/one-optimized.mp4"
        settings.videos[0].optimizedProfile = .efficient

        let manifest = try XCTUnwrap(ScreenSaverManifestBuilder.build(
            settings: settings,
            connectedDisplayIDs: ["display"],
            isReadableFile: { _ in true }
        ))

        XCTAssertEqual(manifest.displays[0].orderedVideoPaths, ["/one-optimized.mp4"])
    }

    func testPerformanceModeFallsBackWhenOptimizedCopyIsMissing() throws {
        var settings = makeSettings(mode: .single, videoIDs: ["one"], startVideoID: "one")
        settings.playbackQuality = .performance
        settings.videos[0].optimizedPath = "/one-optimized.mp4"
        settings.videos[0].optimizedProfile = .efficient

        let manifest = try XCTUnwrap(ScreenSaverManifestBuilder.build(
            settings: settings,
            connectedDisplayIDs: ["display"],
            isReadableFile: { $0 != "/one-optimized.mp4" }
        ))

        XCTAssertEqual(manifest.displays[0].orderedVideoPaths, ["/one.mp4"])
    }

    func testOriginalQualityIgnoresOptimizedCopy() throws {
        var settings = makeSettings(mode: .single, videoIDs: ["one"], startVideoID: "one")
        settings.videos[0].optimizedPath = "/one-optimized.mp4"
        settings.videos[0].optimizedProfile = .efficient

        let manifest = try XCTUnwrap(build(settings))

        XCTAssertEqual(manifest.displays[0].orderedVideoPaths, ["/one.mp4"])
    }

    func testOlderSettingsDefaultToOriginalQuality() throws {
        let legacyJSON = #"{"videos":[],"screens":[],"isMuted":true,"scaling":"Fill screen"}"#

        let decoded = try JSONDecoder().decode(
            WallpaperSettings.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(decoded.playbackQuality, .original)
        XCTAssertEqual(decoded.optimizationProfile, .efficient)
    }

    private func build(_ settings: WallpaperSettings) -> ScreenSaverManifest? {
        ScreenSaverManifestBuilder.build(
            settings: settings,
            connectedDisplayIDs: ["display"],
            isReadableFile: { _ in true }
        )
    }

    private func makeSettings(
        mode: PlaybackMode,
        videoIDs: [String],
        startVideoID: String
    ) -> WallpaperSettings {
        WallpaperSettings(
            videos: makeVideos(["one", "two", "three", "missing"]),
            screens: [ScreenConfiguration(
                screenID: "display",
                screenName: "Display",
                mode: mode,
                videoIDs: videoIDs,
                startVideoID: startVideoID
            )]
        )
    }

    private func makeConfiguration(id: String, videoID: String) -> ScreenConfiguration {
        ScreenConfiguration(
            screenID: id,
            screenName: id,
            videoIDs: [videoID],
            startVideoID: videoID
        )
    }

    private func makeVideos(_ ids: [String]) -> [ManagedVideo] {
        ids.map { ManagedVideo(id: $0, displayName: $0, path: "/\($0).mp4") }
    }
}
