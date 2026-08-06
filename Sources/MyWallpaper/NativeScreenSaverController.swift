import AppKit
import Foundation

enum ScreenSaverIntegrationState: Equatable {
    case moduleUnavailable(message: String)
    case notInstalled
    case updateRequired
    case verificationRequired
    case verificationDenied
    case notSelected(currentName: String?)
    case ready

    var isReady: Bool { self == .ready }
}

enum NativeStartResult: Equatable {
    case started
    case requiresSetup(ScreenSaverIntegrationState)
    case invalidConfiguration(message: String)
    case launchFailed(message: String)
}

final class NativeScreenSaverController {
    private let moduleManager: ScreenSaverModuleManaging
    private let systemService: SystemScreenSaverSelecting
    private let applicationLauncher: WorkspaceApplicationLaunching

    init(
        moduleManager: ScreenSaverModuleManaging = ScreenSaverModuleInstaller(),
        systemService: SystemScreenSaverSelecting? = nil,
        applicationLauncher: WorkspaceApplicationLaunching = WorkspaceApplicationLauncher()
    ) {
        self.moduleManager = moduleManager
        self.applicationLauncher = applicationLauncher
        self.systemService = systemService ?? SystemScreenSaverService(
            applicationLauncher: applicationLauncher
        )
    }

    func integrationState(
        verificationAttempted: Bool,
        requestConsent: Bool = false
    ) async -> ScreenSaverIntegrationState {
        let installedURL: URL
        switch moduleManager.installationState() {
        case let .unavailable(message):
            return .moduleUnavailable(message: message)
        case .notInstalled:
            return .notInstalled
        case .updateRequired:
            return .updateRequired
        case let .current(url):
            installedURL = url
        }

        guard verificationAttempted || requestConsent else {
            return .verificationRequired
        }

        do {
            let selection = try await systemService.selection(requestConsent: requestConsent)
            guard SystemScreenSaverSelectionMatcher.isMyWallpaperSelected(
                selection: selection,
                installedPath: installedURL.path,
                expectedBundleIdentifier: ScreenSaverModuleInstaller.bundleIdentifier,
                bundleIdentifierAtPath: moduleManager.bundleIdentifier(atPath:)
            ) else {
                return .notSelected(currentName: selection.currentName)
            }
            return .ready
        } catch SystemScreenSaverServiceError.automationNotDetermined {
            return .verificationRequired
        } catch SystemScreenSaverServiceError.automationDenied {
            return .verificationDenied
        } catch {
            return .moduleUnavailable(message: error.localizedDescription)
        }
    }

    func installOrUpdate() throws {
        try moduleManager.installOrUpdate()
    }

    func startNativeScreenSaver() async throws {
        guard let url = applicationLauncher.applicationURL(
            bundleIdentifier: "com.apple.ScreenSaver.Engine"
        ) else {
            throw NativeScreenSaverLaunchError.screenSaverEngineUnavailable
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = true
        try await applicationLauncher.openApplication(at: url, configuration: configuration)
    }
}

private enum NativeScreenSaverLaunchError: LocalizedError {
    case screenSaverEngineUnavailable

    var errorDescription: String? {
        "macOS ScreenSaverEngine could not be found or opened."
    }
}
