import XCTest
@testable import MyWallpaper

final class InlinePreviewPlaybackPolicyTests: XCTestCase {
    func testPreviewPlaysOnlyWhenEveryVisibilityConditionAllowsIt() {
        var policy = InlinePreviewPlaybackPolicy(
            applicationIsActive: true,
            windowIsVisible: true,
            displaysPageIsVisible: true,
            competingPlaybackIsActive: false
        )

        XCTAssertTrue(policy.shouldPlay)

        policy.applicationIsActive = false
        XCTAssertFalse(policy.shouldPlay)
        policy.applicationIsActive = true

        policy.windowIsVisible = false
        XCTAssertFalse(policy.shouldPlay)
        policy.windowIsVisible = true

        policy.displaysPageIsVisible = false
        XCTAssertFalse(policy.shouldPlay)
        policy.displaysPageIsVisible = true

        policy.competingPlaybackIsActive = true
        XCTAssertFalse(policy.shouldPlay)
    }
}
