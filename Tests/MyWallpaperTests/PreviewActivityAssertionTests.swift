import IOKit.pwr_mgt
import XCTest
@testable import MyWallpaper

final class PreviewActivityAssertionTests: XCTestCase {
    func testSuccessfulAssertionIsReleasedExactlyOnce() {
        var releasedIDs: [IOPMAssertionID] = []
        let assertion = PreviewActivityAssertion(
            acquireOperation: { assertionID in
                assertionID = 42
                return kIOReturnSuccess
            },
            releaseOperation: { assertionID in
                releasedIDs.append(assertionID)
                return kIOReturnSuccess
            }
        )

        XCTAssertTrue(assertion.acquire())
        assertion.release()
        assertion.release()

        XCTAssertEqual(releasedIDs, [42])
    }

    func testFailedAssertionIsNeverReleased() {
        var releaseCount = 0
        let assertion = PreviewActivityAssertion(
            acquireOperation: { assertionID in
                assertionID = 99
                return kIOReturnError
            },
            releaseOperation: { _ in
                releaseCount += 1
                return kIOReturnSuccess
            }
        )

        XCTAssertFalse(assertion.acquire())
        assertion.release()

        XCTAssertEqual(releaseCount, 0)
    }

    func testReacquiringReleasesThePreviousAssertion() {
        var nextID = IOPMAssertionID(1)
        var releasedIDs: [IOPMAssertionID] = []
        let assertion = PreviewActivityAssertion(
            acquireOperation: { assertionID in
                assertionID = nextID
                nextID += 1
                return kIOReturnSuccess
            },
            releaseOperation: { assertionID in
                releasedIDs.append(assertionID)
                return kIOReturnSuccess
            }
        )

        XCTAssertTrue(assertion.acquire())
        XCTAssertTrue(assertion.acquire())
        assertion.release()

        XCTAssertEqual(releasedIDs, [1, 2])
    }
}
