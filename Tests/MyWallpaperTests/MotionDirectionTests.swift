import XCTest
@testable import MyWallpaper

final class MotionDirectionTests: XCTestCase {
    func testAutomaticAppearanceDoesNotOverrideTheSystemScheme() {
        XCTAssertNil(AppearanceMode.automatic.colorScheme)
    }

    func testExplicitAppearanceModesUseTheirMatchingColorSchemes() {
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
    }

    func testMovingToLaterDisplayMovesContentLeft() {
        XCTAssertEqual(RetroHorizontalMotion.direction(from: 0, to: 2), .left)
    }

    func testMovingToEarlierDisplayMovesContentRight() {
        XCTAssertEqual(RetroHorizontalMotion.direction(from: 2, to: 0), .right)
    }
}
