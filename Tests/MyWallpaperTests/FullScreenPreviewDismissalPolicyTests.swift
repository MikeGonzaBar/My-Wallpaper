import XCTest
@testable import MyWallpaper

final class FullScreenPreviewDismissalPolicyTests: XCTestCase {
    func testLocalInputIsIgnoredUntilInputIsArmed() {
        var policy = FullScreenPreviewDismissalPolicy()
        policy.activate()

        XCTAssertFalse(policy.shouldDismiss(for: .localInput))
        XCTAssertTrue(policy.isActive)

        policy.armInput()

        XCTAssertTrue(policy.shouldDismiss(for: .localInput))
        XCTAssertFalse(policy.isActive)
        XCTAssertFalse(policy.isInputArmed)
    }

    func testLifecycleEventsDismissImmediately() {
        let events: [FullScreenPreviewDismissalEvent] = [
            .applicationResignedActive,
            .displayConfigurationChanged,
            .systemWillSleep,
            .sessionResigned,
            .timeout
        ]

        for event in events {
            var policy = FullScreenPreviewDismissalPolicy()
            policy.activate()

            XCTAssertTrue(policy.shouldDismiss(for: event), "Expected \(event) to dismiss")
            XCTAssertFalse(policy.isActive)
        }
    }

    func testInactiveAndRepeatedEventsDoNotDismissAgain() {
        var policy = FullScreenPreviewDismissalPolicy()

        XCTAssertFalse(policy.shouldDismiss(for: .timeout))

        policy.activate()
        XCTAssertTrue(policy.shouldDismiss(for: .applicationResignedActive))
        XCTAssertFalse(policy.shouldDismiss(for: .applicationResignedActive))
    }

    func testDeactivationClearsArmedState() {
        var policy = FullScreenPreviewDismissalPolicy()
        policy.activate()
        policy.armInput()

        policy.deactivate()

        XCTAssertFalse(policy.isActive)
        XCTAssertFalse(policy.isInputArmed)
    }
}
