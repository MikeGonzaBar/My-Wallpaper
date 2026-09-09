import AppKit
import CoreServices
import Foundation

struct SystemScreenSaverSelection: Equatable, Sendable {
    let currentName: String?
    let currentPath: String?
    let installedNames: [String]
    let installedPaths: [String]
}

enum SystemScreenSaverSelectionParser {
    static func parse(_ descriptor: NSAppleEventDescriptor) -> SystemScreenSaverSelection? {
        guard descriptor.numberOfItems == 4,
              let currentName = descriptor.atIndex(1)?.stringValue,
              !currentName.isEmpty else { return nil }

        let installedNames = strings(in: descriptor.atIndex(3))
        let installedPaths = strings(in: descriptor.atIndex(4))
        let reportedPath = descriptor.atIndex(2)?.stringValue
        return SystemScreenSaverSelection(
            currentName: currentName,
            currentPath: reportedPath?.isEmpty == false ? reportedPath : nil,
            installedNames: installedNames,
            installedPaths: installedPaths
        )
    }

    private static func strings(in descriptor: NSAppleEventDescriptor?) -> [String] {
        let count = descriptor?.numberOfItems ?? 0
        guard count > 0 else { return [] }
        return (1...count).compactMap { descriptor?.atIndex($0)?.stringValue }
    }
}

enum SystemScreenSaverSelectionMatcher {
    static func isMyWallpaperSelected(
        selection: SystemScreenSaverSelection,
        installedPath: String,
        expectedBundleIdentifier: String,
        expectedName: String = "My Wallpaper",
        bundleIdentifierAtPath: (String) -> String?
    ) -> Bool {
        let canonicalInstalled = canonicalPath(installedPath)
        guard selection.currentName == expectedName,
              bundleIdentifierAtPath(canonicalInstalled) == expectedBundleIdentifier else {
            return false
        }

        if let currentPath = selection.currentPath {
            let canonicalSelected = canonicalPath(currentPath)
            let recognized = Set(selection.installedPaths.map(canonicalPath))
            return canonicalSelected == canonicalInstalled && recognized.contains(canonicalInstalled)
        }

        // macOS 26 can return -10000 for the documented path property. A unique
        // recognized name remains fail-closed without consulting private preferences.
        return selection.installedNames.filter { $0 == expectedName }.count == 1
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

enum SystemScreenSaverServiceError: LocalizedError, Equatable, Sendable {
    case automationNotDetermined
    case automationDenied
    case systemEventsUnavailable
    case selectionTemporarilyUnavailable
    case scriptFailed

    var errorDescription: String? {
        switch self {
        case .automationNotDetermined:
            "Verify System Setup to let My Wallpaper check the selected screen saver."
        case .automationDenied:
            "Allow My Wallpaper to control System Events in Privacy & Security → Automation."
        case .systemEventsUnavailable:
            "macOS System Events could not be opened."
        case .selectionTemporarilyUnavailable:
            "macOS is still refreshing the selected screen saver."
        case .scriptFailed:
            "macOS could not report the selected screen saver."
        }
    }
}

protocol SystemScreenSaverSelecting {
    func selection(requestConsent: Bool) async throws -> SystemScreenSaverSelection
}

final class SystemScreenSaverService: SystemScreenSaverSelecting {
    private let applicationLauncher: WorkspaceApplicationLaunching
    private let scriptExecutor = ScreenSaverAppleScriptExecutor()
    private let systemEventsBundleID = "com.apple.systemevents"

    init(applicationLauncher: WorkspaceApplicationLaunching = WorkspaceApplicationLauncher()) {
        self.applicationLauncher = applicationLauncher
    }

    func selection(requestConsent: Bool) async throws -> SystemScreenSaverSelection {
        try await ensureSystemEventsIsRunning()
        try await determineAutomationPermission(requestConsent: requestConsent)
        return try await querySelection()
    }

    private func ensureSystemEventsIsRunning() async throws {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: systemEventsBundleID).isEmpty {
            return
        }
        guard let url = applicationLauncher.applicationURL(bundleIdentifier: systemEventsBundleID) else {
            throw SystemScreenSaverServiceError.systemEventsUnavailable
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        try await applicationLauncher.openApplication(at: url, configuration: configuration)
    }

    private func determineAutomationPermission(requestConsent: Bool) async throws {
        let bundleID = systemEventsBundleID
        let status = await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            guard let descriptor = target.aeDesc else { return OSStatus(paramErr) }
            return AEDeterminePermissionToAutomateTarget(
                descriptor,
                typeWildCard,
                typeWildCard,
                requestConsent
            )
        }.value

        switch status {
        case noErr:
            return
        case OSStatus(errAEEventWouldRequireUserConsent):
            throw SystemScreenSaverServiceError.automationNotDetermined
        case OSStatus(errAEEventNotPermitted):
            throw SystemScreenSaverServiceError.automationDenied
        default:
            throw SystemScreenSaverServiceError.systemEventsUnavailable
        }
    }

    private func querySelection() async throws -> SystemScreenSaverSelection {
        let source = """
        tell application "System Events"
            set selectedSaver to current screen saver
            set selectedName to name of selectedSaver
            set selectedPath to ""
            try
                set selectedPath to POSIX path of (path of selectedSaver)
            end try
            set recognizedNames to {}
            set recognizedPaths to {}
            repeat with saverItem in screen savers
                try
                    set end of recognizedNames to name of saverItem
                end try
                try
                    set end of recognizedPaths to POSIX path of (path of saverItem)
                end try
            end repeat
            return {selectedName, selectedPath, recognizedNames, recognizedPaths}
        end tell
        """

        return try await scriptExecutor.querySelection(source: source)
    }

    static func mapScriptError(_ error: NSDictionary?) -> SystemScreenSaverServiceError {
        let number = error?[NSAppleScript.errorNumber] as? NSNumber
        if number?.intValue == Int(errAEEventNotPermitted) {
            return .automationDenied
        }
        if number?.intValue == Int(errAENoSuchObject) {
            return .selectionTemporarilyUnavailable
        }
        return .scriptFailed
    }

}

private actor ScreenSaverAppleScriptExecutor {
    func querySelection(source: String) throws -> SystemScreenSaverSelection {
        guard let script = NSAppleScript(source: source) else {
            throw SystemScreenSaverServiceError.scriptFailed
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard let selection = SystemScreenSaverSelectionParser.parse(result) else {
            throw SystemScreenSaverService.mapScriptError(error)
        }
        return selection
    }
}
