import XCTest
@testable import MyWallpaper

final class PlaylistOrderingTests: XCTestCase {
    static let allTests = [
        ("testStartsAtChosenVideoAndWrapsEarlierVideosToEnd", testStartsAtChosenVideoAndWrapsEarlierVideosToEnd),
        ("testInvalidStartIndexFallsBackToOriginalOrder", testInvalidStartIndexFallsBackToOriginalOrder),
        ("testSwitchingModesPreservesPlaylist", testSwitchingModesPreservesPlaylist),
        ("testSettingsRoundTripPreservesPerDisplayPlaylist", testSettingsRoundTripPreservesPerDisplayPlaylist)
    ]

    func testStartsAtChosenVideoAndWrapsEarlierVideosToEnd() {
        let videos = ["one", "two", "three"].map {
            URL(fileURLWithPath: "/\($0).mp4")
        }
        let plan = ScreenPlaybackPlan(screenID: "display", videoURLs: videos, startIndex: 1)

        XCTAssertEqual(
            plan.orderedVideoURLs.map(\.lastPathComponent),
            ["two.mp4", "three.mp4", "one.mp4"]
        )
    }

    func testInvalidStartIndexFallsBackToOriginalOrder() {
        let videos = ["one", "two"].map { URL(fileURLWithPath: "/\($0).mp4") }
        let plan = ScreenPlaybackPlan(screenID: "display", videoURLs: videos, startIndex: 9)

        XCTAssertEqual(plan.orderedVideoURLs, videos)
    }

    func testSwitchingModesPreservesPlaylist() {
        var configuration = ScreenConfiguration(
            screenID: "display",
            screenName: "Studio Display",
            mode: .playlist,
            videoIDs: ["one", "two", "three"],
            startVideoID: "two"
        )

        configuration.changeMode(to: .single)
        XCTAssertEqual(configuration.videoIDs, ["two"])

        configuration.changeMode(to: .playlist)
        XCTAssertEqual(configuration.videoIDs, ["one", "two", "three"])
        XCTAssertEqual(configuration.startVideoID, "two")
    }

    func testSwitchingToSingleWithoutAStartKeepsTheFirstVideo() {
        var configuration = ScreenConfiguration(
            screenID: "display",
            screenName: "Studio Display",
            mode: .playlist,
            videoIDs: ["one", "two"],
            startVideoID: nil
        )

        configuration.changeMode(to: .single)

        XCTAssertEqual(configuration.videoIDs, ["one"])
        XCTAssertEqual(configuration.startVideoID, "one")
        XCTAssertEqual(configuration.stashedPlaylistVideoIDs, ["one", "two"])
    }

    func testSwitchingToPlaylistWithoutStashedVideosRetainsTheCurrentSelection() {
        var configuration = ScreenConfiguration(
            screenID: "display",
            screenName: "Studio Display",
            mode: .single,
            videoIDs: ["one"],
            startVideoID: "one"
        )

        configuration.changeMode(to: .playlist)

        XCTAssertEqual(configuration.videoIDs, ["one"])
        XCTAssertEqual(configuration.startVideoID, "one")
        XCTAssertTrue(configuration.stashedPlaylistVideoIDs.isEmpty)
    }

    func testSettingsRoundTripPreservesPerDisplayPlaylist() throws {
        let video = ManagedVideo(id: "video", displayName: "Ocean", path: "/ocean.mp4")
        let screen = ScreenConfiguration(
            screenID: "display",
            screenName: "Studio Display",
            mode: .playlist,
            videoIDs: [video.id],
            startVideoID: video.id
        )
        let settings = WallpaperSettings(videos: [video], screens: [screen])

        let decoded = try JSONDecoder().decode(
            WallpaperSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded, settings)
    }

    func testRollingPlaylistBuffersAtMostTwoItemsAndWraps() {
        let urls = ["one", "two", "three"].map {
            URL(fileURLWithPath: "/\($0).mp4")
        }
        var state = RollingPlaylistState(orderedURLs: urls)

        XCTAssertEqual(state.targetBufferedItemCount, 2)
        XCTAssertEqual(state.nextPlayableURL(), urls[0])
        XCTAssertEqual(state.nextPlayableURL(), urls[1])
        XCTAssertEqual(state.nextPlayableURL(), urls[2])
        XCTAssertEqual(state.nextPlayableURL(), urls[0])
    }

    func testRollingPlaylistPermanentlySkipsFailedURLs() {
        let urls = ["one", "two", "three"].map {
            URL(fileURLWithPath: "/\($0).mp4")
        }
        var state = RollingPlaylistState(orderedURLs: urls)
        state.markFailed(urls[1])

        XCTAssertEqual(state.targetBufferedItemCount, 2)
        XCTAssertEqual(state.nextPlayableURL(), urls[0])
        XCTAssertEqual(state.nextPlayableURL(), urls[2])
        XCTAssertEqual(state.nextPlayableURL(), urls[0])
    }

    func testRollingPlaylistStopsAfterEveryUniqueURLFails() {
        let repeatedURL = URL(fileURLWithPath: "/repeated.mp4")
        var state = RollingPlaylistState(orderedURLs: [repeatedURL, repeatedURL])

        XCTAssertEqual(state.targetBufferedItemCount, 1)
        state.markFailed(repeatedURL)

        XCTAssertFalse(state.hasPlayableURL)
        XCTAssertEqual(state.targetBufferedItemCount, 0)
        XCTAssertNil(state.nextPlayableURL())
    }

    func testRollingPlaylistSkipsFailuresAfterItsCursorHasAdvanced() {
        let urls = ["one", "two", "three"].map {
            URL(fileURLWithPath: "/\($0).mp4")
        }
        var state = RollingPlaylistState(orderedURLs: urls)

        XCTAssertEqual(state.nextPlayableURL(), urls[0])
        state.markFailed(urls[1])

        XCTAssertEqual(state.nextPlayableURL(), urls[2])
        XCTAssertEqual(state.nextPlayableURL(), urls[0])
        XCTAssertEqual(state.targetBufferedItemCount, 2)
    }

    func testRollingPlaylistWithNoURLsNeverAttemptsPlayback() {
        var state = RollingPlaylistState(orderedURLs: [])

        XCTAssertFalse(state.hasPlayableURL)
        XCTAssertEqual(state.targetBufferedItemCount, 0)
        XCTAssertNil(state.nextPlayableURL())
    }
}
