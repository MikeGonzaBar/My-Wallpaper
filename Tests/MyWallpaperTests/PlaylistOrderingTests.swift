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
}
