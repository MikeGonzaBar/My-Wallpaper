import ServiceManagement
import XCTest
@testable import MyWallpaper

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testMapsEverySystemStatus() {
        XCTAssertEqual(SystemLaunchAtLoginManager.state(for: .notRegistered), .disabled)
        XCTAssertEqual(SystemLaunchAtLoginManager.state(for: .enabled), .enabled)
        XCTAssertEqual(SystemLaunchAtLoginManager.state(for: .requiresApproval), .requiresApproval)
        XCTAssertEqual(SystemLaunchAtLoginManager.state(for: .notFound), .unavailable)
    }

    func testEnablingRegistersAndRefreshesStatus() async {
        let manager = StubLaunchAtLoginManager(state: .disabled)
        manager.stateAfterRegister = .enabled
        let controller = LaunchAtLoginController(manager: manager)

        await controller.setEnabled(true)

        XCTAssertEqual(manager.registerCallCount, 1)
        XCTAssertEqual(controller.state, .enabled)
        XCTAssertNil(controller.errorMessage)
    }

    func testDisablingUnregistersAndRefreshesStatus() async {
        let manager = StubLaunchAtLoginManager(state: .enabled)
        manager.stateAfterUnregister = .disabled
        let controller = LaunchAtLoginController(manager: manager)

        await controller.setEnabled(false)

        XCTAssertEqual(manager.unregisterCallCount, 1)
        XCTAssertEqual(controller.state, .disabled)
    }

    func testRequestsMatchingCurrentStateAreNoOps() async {
        let enabledManager = StubLaunchAtLoginManager(state: .enabled)
        let enabledController = LaunchAtLoginController(manager: enabledManager)
        let disabledManager = StubLaunchAtLoginManager(state: .disabled)
        let disabledController = LaunchAtLoginController(manager: disabledManager)

        await enabledController.setEnabled(true)
        await disabledController.setEnabled(false)

        XCTAssertEqual(enabledManager.registerCallCount, 0)
        XCTAssertEqual(disabledManager.unregisterCallCount, 0)
    }

    func testApprovalRequiredDoesNotAttemptRegistrationAgain() async {
        let manager = StubLaunchAtLoginManager(state: .requiresApproval)
        let controller = LaunchAtLoginController(manager: manager)

        await controller.setEnabled(true)

        XCTAssertEqual(manager.registerCallCount, 0)
        XCTAssertEqual(controller.state, .requiresApproval)
    }

    func testRegisterFailureIsReportedAndStatusIsRefreshed() async {
        let manager = StubLaunchAtLoginManager(state: .disabled)
        manager.registerError = TestError.operationFailed
        let controller = LaunchAtLoginController(manager: manager)

        await controller.setEnabled(true)

        XCTAssertEqual(controller.state, .disabled)
        XCTAssertTrue(controller.errorMessage?.contains("couldn’t be enabled") == true)
    }

    func testUnregisterFailureIsReportedAndStatusIsRefreshed() async {
        let manager = StubLaunchAtLoginManager(state: .enabled)
        manager.unregisterError = TestError.operationFailed
        let controller = LaunchAtLoginController(manager: manager)

        await controller.setEnabled(false)

        XCTAssertEqual(controller.state, .enabled)
        XCTAssertTrue(controller.errorMessage?.contains("couldn’t be disabled") == true)
    }

    func testUnavailableStateCanAttemptRepairRegistration() async {
        let manager = StubLaunchAtLoginManager(state: .unavailable)
        manager.stateAfterRegister = .enabled
        let controller = LaunchAtLoginController(manager: manager)

        await controller.setEnabled(true)

        XCTAssertEqual(manager.registerCallCount, 1)
        XCTAssertEqual(controller.state, .enabled)
    }

    func testRefreshReflectsExternalStateChange() {
        let manager = StubLaunchAtLoginManager(state: .disabled)
        let controller = LaunchAtLoginController(manager: manager)

        manager.state = .enabled
        controller.refresh()

        XCTAssertEqual(controller.state, .enabled)
    }

    func testOpenSystemSettingsDelegatesToManager() {
        let manager = StubLaunchAtLoginManager(state: .requiresApproval)
        let controller = LaunchAtLoginController(manager: manager)

        controller.openSystemSettings()

        XCTAssertEqual(manager.openSettingsCallCount, 1)
    }
}

private enum TestError: LocalizedError {
    case operationFailed

    var errorDescription: String? { "Operation failed" }
}

private final class StubLaunchAtLoginManager: LaunchAtLoginManaging {
    var state: LaunchAtLoginState
    var stateAfterRegister: LaunchAtLoginState?
    var stateAfterUnregister: LaunchAtLoginState?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(state: LaunchAtLoginState) {
        self.state = state
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        if let stateAfterRegister { state = stateAfterRegister }
    }

    func unregister() async throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        if let stateAfterUnregister { state = stateAfterUnregister }
    }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}
