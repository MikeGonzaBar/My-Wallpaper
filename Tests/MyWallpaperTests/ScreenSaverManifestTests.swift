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
        XCTAssertEqual(decoded.configurationGeneration, settings.configurationGeneration)
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

    func testSettingsEncodeStableTokensAndDecodeLegacyPresentationValues() throws {
        let settings = WallpaperSettings(
            screens: [ScreenConfiguration(
                screenID: "display",
                screenName: "Display",
                mode: .playlist
            )],
            scaling: .fit,
            playbackQuality: .performance,
            optimizationProfile: .maximum
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
        )
        XCTAssertEqual(object["scaling"] as? String, "fit")
        XCTAssertEqual(object["playbackQuality"] as? String, "performance")
        XCTAssertEqual(object["optimizationProfile"] as? String, "maximum")
        let screens = try XCTUnwrap(object["screens"] as? [[String: Any]])
        XCTAssertEqual(screens[0]["mode"] as? String, "playlist")

        let legacyJSON = #"{"videos":[],"screens":[{"screenID":"display","screenName":"Display","mode":"Single video","videoIDs":[],"stashedPlaylistVideoIDs":[]}],"isMuted":true,"scaling":"Fit to screen","playbackQuality":"Original quality","optimizationProfile":"1440p / 60 FPS"}"#
        let decoded = try JSONDecoder().decode(
            WallpaperSettings.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertEqual(decoded.scaling, .fit)
        XCTAssertEqual(decoded.playbackQuality, .original)
        XCTAssertEqual(decoded.optimizationProfile, .efficient)
        XCTAssertEqual(decoded.screens[0].mode, .single)
    }

    func testEverySupportedLegacyPresentationTokenRemainsDecodable() throws {
        XCTAssertEqual(try decode(VideoScaling.self, from: "Fill screen"), .fill)
        XCTAssertEqual(try decode(VideoScaling.self, from: "Fit to screen"), .fit)
        XCTAssertEqual(try decode(PlaybackMode.self, from: "Single video"), .single)
        XCTAssertEqual(try decode(PlaybackMode.self, from: "Playlist"), .playlist)
        XCTAssertEqual(try decode(VideoPlaybackQuality.self, from: "Original quality"), .original)
        XCTAssertEqual(try decode(VideoPlaybackQuality.self, from: "Performance mode"), .performance)
        XCTAssertEqual(try decode(VideoOptimizationProfile.self, from: "1440p / 60 FPS"), .efficient)
        XCTAssertEqual(try decode(VideoOptimizationProfile.self, from: "4K / 60 FPS"), .maximum)
    }

    func testUnknownPersistedEnumAndFutureSchemaAreRejected() {
        let unknownValue = #"{"schemaVersion":1,"videos":[],"screens":[],"isMuted":true,"scaling":"stretch"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(
            WallpaperSettings.self,
            from: Data(unknownValue.utf8)
        ))

        let futureSchema = #"{"schemaVersion":999,"videos":[],"screens":[],"isMuted":true,"scaling":"fill"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(
            WallpaperSettings.self,
            from: Data(futureSchema.utf8)
        ))
    }

    func testRepairRemovesAmbiguousAndDanglingRelationships() {
        let video = ManagedVideo(id: "video", displayName: "Video", path: "/video.mp4")
        let duplicate = ManagedVideo(id: "video", displayName: "Duplicate", path: "/duplicate.mp4")
        let settings = WallpaperSettings(
            videos: [video, duplicate],
            screens: [
                ScreenConfiguration(
                    screenID: "display",
                    screenName: "Display",
                    mode: .playlist,
                    videoIDs: ["missing", "video", "video"],
                    startVideoID: "missing"
                ),
                ScreenConfiguration(screenID: "display", screenName: "Duplicate")
            ]
        )

        let repaired = settings.repaired()

        XCTAssertEqual(repaired.videos, [video])
        XCTAssertEqual(repaired.screens.count, 1)
        XCTAssertEqual(repaired.screens[0].videoIDs, ["video"])
        XCTAssertEqual(repaired.screens[0].startVideoID, "video")
        XCTAssertEqual(repaired.schemaVersion, WallpaperSettings.currentSchemaVersion)
    }

    func testRepairClearsPartialOptimizationStateAndRepairsStartsIndependently() {
        let originalOnly = ManagedVideo(
            id: "original-only",
            displayName: "Original only",
            path: "/original.mp4",
            optimizedPath: "/optimized.mp4"
        )
        let profileOnly = ManagedVideo(
            id: "profile-only",
            displayName: "Profile only",
            path: "/profile.mp4",
            optimizedProfile: .efficient
        )
        let settings = WallpaperSettings(
            videos: [originalOnly, profileOnly],
            screens: [
                ScreenConfiguration(
                    screenID: "one",
                    screenName: "One",
                    videoIDs: ["original-only"],
                    startVideoID: "missing"
                ),
                ScreenConfiguration(
                    screenID: "two",
                    screenName: "Two",
                    videoIDs: ["profile-only"],
                    startVideoID: "profile-only"
                )
            ]
        )

        let repaired = settings.repaired()

        XCTAssertNil(repaired.videos[0].optimizedPath)
        XCTAssertNil(repaired.videos[0].optimizedProfile)
        XCTAssertNil(repaired.videos[1].optimizedPath)
        XCTAssertNil(repaired.videos[1].optimizedProfile)
        XCTAssertEqual(repaired.screens.map(\.startVideoID), ["original-only", "profile-only"])
    }

    func testModernEmptyScreenStateIsNotTreatedAsLegacyMigration() {
        let video = ManagedVideo(id: "video", displayName: "Video", path: "/video.mp4")
        let settings = WallpaperSettings(videos: [video], screens: [])
        let displays = [DisplayInfo(id: "display", name: "Display")]

        let modern = WallpaperSettingsMigration.assigningLegacyVideoIfNeeded(
            in: settings,
            displays: displays,
            decodedFromLegacyFormat: false
        )
        let legacy = WallpaperSettingsMigration.assigningLegacyVideoIfNeeded(
            in: settings,
            displays: displays,
            decodedFromLegacyFormat: true
        )

        XCTAssertTrue(modern.screens.isEmpty)
        XCTAssertEqual(legacy.screens.first?.videoIDs, [video.id])
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

    private func decode<Value: Decodable>(_ type: Value.Type, from value: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data("\"\(value)\"".utf8))
    }
}
