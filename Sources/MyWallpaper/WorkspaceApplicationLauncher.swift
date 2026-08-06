import AppKit

protocol WorkspaceApplicationLaunching {
    func applicationURL(bundleIdentifier: String) -> URL?
    func openApplication(
        at url: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async throws
}

final class WorkspaceApplicationLauncher: WorkspaceApplicationLaunching {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func openApplication(
        at url: URL,
        configuration: NSWorkspace.OpenConfiguration
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.openApplication(at: url, configuration: configuration) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if application == nil {
                    continuation.resume(throwing: WorkspaceApplicationLaunchError.noApplicationReturned)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private enum WorkspaceApplicationLaunchError: LocalizedError {
    case noApplicationReturned

    var errorDescription: String? {
        "macOS did not open the requested application."
    }
}
