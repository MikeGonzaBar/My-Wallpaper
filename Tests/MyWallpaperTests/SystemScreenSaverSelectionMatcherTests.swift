import AppKit
import XCTest
@testable import MyWallpaper

final class SystemScreenSaverSelectionMatcherTests: XCTestCase {
    private let expectedBundleID = "com.prototype.mywallpaper.saver"
    private let installedPath = "/Users/test/Library/Screen Savers/My Wallpaper.saver"

    func testMatchesCanonicalSelectedAndRecognizedPath() {
        let selection = SystemScreenSaverSelection(
            currentName: "My Wallpaper",
            currentPath: "/Users/test/Library/Screen Savers/../Screen Savers/My Wallpaper.saver",
            installedNames: ["My Wallpaper"],
            installedPaths: [installedPath]
        )

        XCTAssertTrue(matches(selection) { _ in self.expectedBundleID })
    }

    func testRejectsDifferentSelectedSaver() {
        let selection = SystemScreenSaverSelection(
            currentName: "Tahoe Day",
            currentPath: "/System/Tahoe Day.appex",
            installedNames: ["My Wallpaper", "Tahoe Day"],
            installedPaths: [installedPath]
        )

        XCTAssertFalse(matches(selection) { _ in self.expectedBundleID })
    }

    func testRejectsUnrecognizedInstallation() {
        let selection = SystemScreenSaverSelection(
            currentName: "My Wallpaper",
            currentPath: installedPath,
            installedNames: ["My Wallpaper"],
            installedPaths: []
        )

        XCTAssertFalse(matches(selection) { _ in self.expectedBundleID })
    }

    func testRejectsWrongBundleIdentifier() {
        let selection = SystemScreenSaverSelection(
            currentName: "My Wallpaper",
            currentPath: installedPath,
            installedNames: ["My Wallpaper"],
            installedPaths: [installedPath]
        )

        XCTAssertFalse(matches(selection) { _ in "example.wrong" })
    }

    func testOnlyReadyIntegrationStateIsReady() {
        XCTAssertTrue(ScreenSaverIntegrationState.ready.isReady)
        XCTAssertFalse(ScreenSaverIntegrationState.updateRequired.isReady)
        XCTAssertFalse(ScreenSaverIntegrationState.finalizingUpdate.isReady)
        XCTAssertFalse(ScreenSaverIntegrationState.verificationDenied.isReady)
    }

    func testMatchesUniqueRecognizedNameWhenSystemEventsPathIsUnavailable() {
        let selection = SystemScreenSaverSelection(
            currentName: "My Wallpaper",
            currentPath: nil,
            installedNames: ["Tahoe Day", "My Wallpaper"],
            installedPaths: []
        )

        XCTAssertTrue(matches(selection) { _ in self.expectedBundleID })
    }

    func testRejectsAmbiguousRecognizedNameWhenPathIsUnavailable() {
        let selection = SystemScreenSaverSelection(
            currentName: "My Wallpaper",
            currentPath: nil,
            installedNames: ["My Wallpaper", "My Wallpaper"],
            installedPaths: []
        )

        XCTAssertFalse(matches(selection) { _ in self.expectedBundleID })
    }

    func testParsesSystemEventsDescriptorIncludingRecognizedPaths() throws {
        let descriptor = makeSelectionDescriptor(
            installedNames: ["My Wallpaper", "Other"],
            installedPaths: [installedPath, "/Other.saver"]
        )

        let parsed = try XCTUnwrap(SystemScreenSaverSelectionParser.parse(descriptor))

        XCTAssertEqual(parsed.currentName, "My Wallpaper")
        XCTAssertEqual(parsed.currentPath, installedPath)
        XCTAssertEqual(parsed.installedNames, ["My Wallpaper", "Other"])
        XCTAssertEqual(parsed.installedPaths, [installedPath, "/Other.saver"])
    }

    func testParsesSystemEventsDescriptorWithNoRecognizedPaths() throws {
        let descriptor = makeSelectionDescriptor(
            currentPath: "",
            installedNames: ["My Wallpaper"],
            installedPaths: []
        )

        let parsed = try XCTUnwrap(SystemScreenSaverSelectionParser.parse(descriptor))

        XCTAssertNil(parsed.currentPath)
        XCTAssertEqual(parsed.installedNames, ["My Wallpaper"])
        XCTAssertEqual(parsed.installedPaths, [])
    }

    func testRejectsIncompleteSystemEventsDescriptor() {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "My Wallpaper"), at: 1)

        XCTAssertNil(SystemScreenSaverSelectionParser.parse(descriptor))
    }

    func testMapsMissingScreenSaverObjectAsTransient() {
        let error: NSDictionary = [
            NSAppleScript.errorNumber: NSNumber(value: -1728)
        ]

        XCTAssertEqual(
            SystemScreenSaverService.mapScriptError(error),
            .selectionTemporarilyUnavailable
        )
    }

    func testIntegrationStateStopsAtModuleReadiness() async {
        let service = StubSystemScreenSaverService(result: .failure(.automationDenied))

        let missing = await makeController(state: .notInstalled, service: service)
            .integrationState(verificationAttempted: true)
        let stale = await makeController(state: .updateRequired, service: service)
            .integrationState(verificationAttempted: true)

        XCTAssertEqual(missing, .notInstalled)
        XCTAssertEqual(stale, .updateRequired)
        XCTAssertEqual(service.requestConsentValues, [])
    }

    func testIntegrationStateRequiresExplicitVerificationBeforeQuerying() async {
        let service = StubSystemScreenSaverService(result: .success(selectedMyWallpaper))

        let state = await makeController(state: .current(installedURL), service: service)
            .integrationState(verificationAttempted: false)

        XCTAssertEqual(state, .verificationRequired)
        XCTAssertEqual(service.requestConsentValues, [])
    }

    func testIntegrationStateMapsAutomationAuthorizationResults() async {
        let notDetermined = StubSystemScreenSaverService(
            result: .failure(.automationNotDetermined)
        )
        let denied = StubSystemScreenSaverService(result: .failure(.automationDenied))

        let notDeterminedState = await makeController(
            state: .current(installedURL),
            service: notDetermined
        ).integrationState(verificationAttempted: true)
        let deniedState = await makeController(
            state: .current(installedURL),
            service: denied
        ).integrationState(verificationAttempted: true)

        XCTAssertEqual(notDeterminedState, .verificationRequired)
        XCTAssertEqual(deniedState, .verificationDenied)
        XCTAssertEqual(notDetermined.requestConsentValues, [false])
        XCTAssertEqual(denied.requestConsentValues, [false])
    }

    func testIntegrationStateFailsClosedWhenSystemEventsIsUnavailable() async {
        let service = StubSystemScreenSaverService(result: .failure(.systemEventsUnavailable))

        let state = await makeController(state: .current(installedURL), service: service)
            .integrationState(verificationAttempted: true)

        XCTAssertEqual(
            state,
            .moduleUnavailable(message: SystemScreenSaverServiceError.systemEventsUnavailable.localizedDescription)
        )
    }

    func testPostUpdateVerificationRetriesTransientSelectionFailure() async {
        let service = SequencedSystemScreenSaverService(results: [
            .failure(.selectionTemporarilyUnavailable),
            .failure(.selectionTemporarilyUnavailable),
            .success(selectedMyWallpaper)
        ])
        let controller = NativeScreenSaverController(
            moduleManager: StubScreenSaverModuleManager(
                state: .current(installedURL),
                bundleIdentifier: expectedBundleID
            ),
            systemService: service,
            transientRetryDelays: [.zero, .zero]
        )

        let state = await controller.integrationState(
            verificationAttempted: true,
            retryTransientSelection: true
        )

        XCTAssertEqual(state, .ready)
        XCTAssertEqual(service.requestConsentValues, [false, false, false])
    }

    func testOrdinaryVerificationDoesNotRetryTransientSelectionFailure() async {
        let service = SequencedSystemScreenSaverService(results: [
            .failure(.selectionTemporarilyUnavailable),
            .success(selectedMyWallpaper)
        ])
        let controller = NativeScreenSaverController(
            moduleManager: StubScreenSaverModuleManager(
                state: .current(installedURL),
                bundleIdentifier: expectedBundleID
            ),
            systemService: service,
            transientRetryDelays: [.zero]
        )

        let state = await controller.integrationState(verificationAttempted: true)

        XCTAssertEqual(
            state,
            .moduleUnavailable(
                message: SystemScreenSaverServiceError.selectionTemporarilyUnavailable
                    .localizedDescription
            )
        )
        XCTAssertEqual(service.requestConsentValues, [false])
    }

    func testIntegrationStateRequestsConsentOnlyWhenDirected() async {
        let service = StubSystemScreenSaverService(result: .success(selectedMyWallpaper))

        let state = await makeController(state: .current(installedURL), service: service)
            .integrationState(verificationAttempted: false, requestConsent: true)

        XCTAssertEqual(state, .ready)
        XCTAssertEqual(service.requestConsentValues, [true])
    }

    func testIntegrationStateReportsWrongSelectionAndReadySelection() async {
        let wrongSelection = SystemScreenSaverSelection(
            currentName: "Tahoe Day",
            currentPath: "/System/Tahoe Day.appex",
            installedNames: ["Tahoe Day", "My Wallpaper"],
            installedPaths: [installedPath]
        )
        let wrongService = StubSystemScreenSaverService(result: .success(wrongSelection))
        let readyService = StubSystemScreenSaverService(result: .success(selectedMyWallpaper))

        let wrong = await makeController(state: .current(installedURL), service: wrongService)
            .integrationState(verificationAttempted: true)
        let ready = await makeController(state: .current(installedURL), service: readyService)
            .integrationState(verificationAttempted: true)

        XCTAssertEqual(wrong, .notSelected(currentName: "Tahoe Day"))
        XCTAssertEqual(ready, .ready)
    }

    func testNativeLaunchFailsWhenScreenSaverEngineCannotBeResolved() async {
        let launcher = StubWorkspaceApplicationLauncher(applicationURL: nil)
        let controller = NativeScreenSaverController(
            moduleManager: StubScreenSaverModuleManager(
                state: .current(installedURL),
                bundleIdentifier: expectedBundleID
            ),
            systemService: StubSystemScreenSaverService(result: .success(selectedMyWallpaper)),
            applicationLauncher: launcher
        )

        do {
            try await controller.startNativeScreenSaver()
            XCTFail("Expected launch to fail when ScreenSaverEngine is unavailable")
        } catch {
            XCTAssertEqual(launcher.openedURLs, [])
        }
    }

    func testNativeLaunchUsesResolvedScreenSaverEngine() async throws {
        let engineURL = URL(fileURLWithPath: "/Applications/ScreenSaverEngine.app")
        let launcher = StubWorkspaceApplicationLauncher(applicationURL: engineURL)
        let controller = NativeScreenSaverController(
            moduleManager: StubScreenSaverModuleManager(
                state: .current(installedURL),
                bundleIdentifier: expectedBundleID
            ),
            systemService: StubSystemScreenSaverService(result: .success(selectedMyWallpaper)),
            applicationLauncher: launcher
        )

        try await controller.startNativeScreenSaver()

        XCTAssertEqual(launcher.openedURLs, [engineURL])
    }

    func testNativeLaunchPropagatesWorkspaceFailure() async {
        let engineURL = URL(fileURLWithPath: "/Applications/ScreenSaverEngine.app")
        let launcher = StubWorkspaceApplicationLauncher(
            applicationURL: engineURL,
            launchError: StubWorkspaceError.launchFailed
        )
        let controller = NativeScreenSaverController(
            moduleManager: StubScreenSaverModuleManager(
                state: .current(installedURL),
                bundleIdentifier: expectedBundleID
            ),
            systemService: StubSystemScreenSaverService(result: .success(selectedMyWallpaper)),
            applicationLauncher: launcher
        )

        await XCTAssertThrowsErrorAsync {
            try await controller.startNativeScreenSaver()
        }
        XCTAssertEqual(launcher.openedURLs, [engineURL])
    }

    private func matches(
        _ selection: SystemScreenSaverSelection,
        bundleIdentifierAtPath: (String) -> String?
    ) -> Bool {
        SystemScreenSaverSelectionMatcher.isMyWallpaperSelected(
            selection: selection,
            installedPath: installedPath,
            expectedBundleIdentifier: expectedBundleID,
            bundleIdentifierAtPath: bundleIdentifierAtPath
        )
    }

    private var installedURL: URL { URL(fileURLWithPath: installedPath) }

    private var selectedMyWallpaper: SystemScreenSaverSelection {
        SystemScreenSaverSelection(
            currentName: "My Wallpaper",
            currentPath: installedPath,
            installedNames: ["My Wallpaper"],
            installedPaths: [installedPath]
        )
    }

    private func makeController(
        state: ScreenSaverModuleInstallationState,
        service: StubSystemScreenSaverService
    ) -> NativeScreenSaverController {
        NativeScreenSaverController(
            moduleManager: StubScreenSaverModuleManager(
                state: state,
                bundleIdentifier: expectedBundleID
            ),
            systemService: service
        )
    }

    private func makeSelectionDescriptor(
        currentPath: String? = nil,
        installedNames: [String],
        installedPaths: [String]
    ) -> NSAppleEventDescriptor {
        let names = NSAppleEventDescriptor.list()
        for (index, name) in installedNames.enumerated() {
            names.insert(NSAppleEventDescriptor(string: name), at: index + 1)
        }
        let paths = NSAppleEventDescriptor.list()
        for (index, path) in installedPaths.enumerated() {
            paths.insert(NSAppleEventDescriptor(string: path), at: index + 1)
        }
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(string: "My Wallpaper"), at: 1)
        descriptor.insert(NSAppleEventDescriptor(string: currentPath ?? installedPath), at: 2)
        descriptor.insert(names, at: 3)
        descriptor.insert(paths, at: 4)
        return descriptor
    }
}

private final class StubScreenSaverModuleManager: ScreenSaverModuleManaging {
    let state: ScreenSaverModuleInstallationState
    let bundleIdentifier: String?

    init(state: ScreenSaverModuleInstallationState, bundleIdentifier: String?) {
        self.state = state
        self.bundleIdentifier = bundleIdentifier
    }

    func installationState() -> ScreenSaverModuleInstallationState { state }
    func installOrUpdate() throws {}
    func bundleIdentifier(atPath path: String) -> String? { bundleIdentifier }
}

private final class StubSystemScreenSaverService: SystemScreenSaverSelecting {
    let result: Result<SystemScreenSaverSelection, SystemScreenSaverServiceError>
    private(set) var requestConsentValues: [Bool] = []

    init(result: Result<SystemScreenSaverSelection, SystemScreenSaverServiceError>) {
        self.result = result
    }

    func selection(requestConsent: Bool) async throws -> SystemScreenSaverSelection {
        requestConsentValues.append(requestConsent)
        return try result.get()
    }
}

private final class SequencedSystemScreenSaverService: SystemScreenSaverSelecting {
    private var results: [Result<SystemScreenSaverSelection, SystemScreenSaverServiceError>]
    private(set) var requestConsentValues: [Bool] = []

    init(results: [Result<SystemScreenSaverSelection, SystemScreenSaverServiceError>]) {
        self.results = results
    }

    func selection(requestConsent: Bool) async throws -> SystemScreenSaverSelection {
        requestConsentValues.append(requestConsent)
        guard !results.isEmpty else { throw SystemScreenSaverServiceError.scriptFailed }
        return try results.removeFirst().get()
    }
}

private final class StubWorkspaceApplicationLauncher: WorkspaceApplicationLaunching {
    let resolvedApplicationURL: URL?
    let launchError: Error?
    private(set) var openedURLs: [URL] = []

    init(applicationURL: URL?, launchError: Error? = nil) {
        resolvedApplicationURL = applicationURL
        self.launchError = launchError
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        resolvedApplicationURL
    }

    func openApplication(
        at url: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async throws {
        openedURLs.append(url)
        if let launchError { throw launchError }
    }
}

private enum StubWorkspaceError: Error {
    case launchFailed
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {}
}
