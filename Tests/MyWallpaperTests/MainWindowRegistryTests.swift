import AppKit
import XCTest
@testable import MyWallpaper

@MainActor
final class MainWindowRegistryTests: XCTestCase {
    func testRegisterAssignsStableIdentifierAndReportsVisibility() {
        let application = StubApplicationPresenter()
        let registry = MainWindowRegistry(application: application)
        let window = StubMainWindow(isEffectivelyVisible: true)

        registry.register(window)

        XCTAssertEqual(window.identifier, MainWindowRegistry.identifier)
        XCTAssertTrue(registry.isVisible)
    }

    func testShowExistingWindowPresentsAndActivatesApplication() {
        let application = StubApplicationPresenter()
        let registry = MainWindowRegistry(application: application)
        let window = StubMainWindow(isEffectivelyVisible: false)
        registry.register(window)

        XCTAssertTrue(registry.showExistingWindow())

        XCTAssertEqual(application.prepareCallCount, 1)
        XCTAssertEqual(application.activateCallCount, 1)
        XCTAssertEqual(window.showCallCount, 1)
    }

    func testMissingWindowRequestsOpenWindowFallback() {
        let application = StubApplicationPresenter()
        let registry = MainWindowRegistry(application: application)

        XCTAssertFalse(registry.showExistingWindow())
        XCTAssertEqual(application.prepareCallCount, 0)
        XCTAssertEqual(application.activateCallCount, 0)
    }

    func testUnregisterIgnoresAWindowThatIsNotRegistered() {
        let registry = MainWindowRegistry(application: StubApplicationPresenter())
        let registered = StubMainWindow(isEffectivelyVisible: true)
        let other = StubMainWindow(isEffectivelyVisible: false)
        registry.register(registered)

        registry.unregister(other)

        XCTAssertTrue(registry.isVisible)
        XCTAssertTrue(registry.showExistingWindow())
        XCTAssertEqual(registered.showCallCount, 1)
    }

    func testHiddenRequestAppliesToCurrentAndLateRegisteredWindows() {
        let registry = MainWindowRegistry(application: StubApplicationPresenter())
        let current = StubMainWindow(isEffectivelyVisible: true)
        registry.register(current)

        registry.requestHiddenWindow()

        XCTAssertEqual(current.hideCallCount, 1)

        let replacement = StubMainWindow(isEffectivelyVisible: true)
        registry.register(replacement)

        XCTAssertEqual(replacement.hideCallCount, 1)
    }

    func testPreparingToOpenClearsDeferredHiddenRequest() {
        let application = StubApplicationPresenter()
        let registry = MainWindowRegistry(application: application)
        registry.requestHiddenWindow()

        registry.prepareToOpenWindow()
        let window = StubMainWindow(isEffectivelyVisible: true)
        registry.register(window)

        XCTAssertEqual(application.prepareCallCount, 1)
        XCTAssertEqual(window.hideCallCount, 0)
    }
}

@MainActor
private final class StubApplicationPresenter: ApplicationPresenting {
    private(set) var prepareCallCount = 0
    private(set) var activateCallCount = 0

    func prepareToPresentWindow() {
        prepareCallCount += 1
    }

    func activate() {
        activateCallCount += 1
    }
}

@MainActor
private final class StubMainWindow: MainWindowControlling {
    var identifier: NSUserInterfaceItemIdentifier?
    var isEffectivelyVisible: Bool
    private(set) var showCallCount = 0
    private(set) var hideCallCount = 0

    init(isEffectivelyVisible: Bool) {
        self.isEffectivelyVisible = isEffectivelyVisible
    }

    func makeKeyAndOrderFront(_ sender: Any?) {
        showCallCount += 1
        isEffectivelyVisible = true
    }

    func orderOut(_ sender: Any?) {
        hideCallCount += 1
        isEffectivelyVisible = false
    }
}
