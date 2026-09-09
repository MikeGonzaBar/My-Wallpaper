import AppKit
import Foundation

@MainActor
final class MacSystemActions {
    var onError: ((String) -> Void)?

    func openScreenSaverSettings() {
        let destination = if #available(macOS 13.0, *) {
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
        } else {
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect"
        }
        guard let url = URL(string: destination) else {
            openSystemSettingsFallback()
            return
        }

        let configuration = workspaceOpenConfiguration()
        NSWorkspace.shared.open(url, configuration: configuration) { [weak self] application, error in
            if error == nil, let application {
                application.activate(options: [.activateAllWindows])
            } else {
                Task { @MainActor [weak self] in
                    self?.openSystemSettingsFallback()
                }
            }
        }
    }

    func openAutomationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        ) else { return }
        NSWorkspace.shared.open(url, configuration: workspaceOpenConfiguration()) { [weak self] application, error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.onError?("Automation settings could not be opened: \(error.localizedDescription)")
                }
            } else {
                application?.activate(options: [.activateAllWindows])
            }
        }
    }

    func sleepDisplays() {
        let powerManager = URL(fileURLWithPath: "/usr/bin/pmset")
        guard FileManager.default.isExecutableFile(atPath: powerManager.path) else {
            onError?("The macOS display-sleep command couldn’t be found.")
            return
        }

        let process = Process()
        process.executableURL = powerManager
        process.arguments = ["displaysleepnow"]
        process.terminationHandler = { [weak self] completedProcess in
            guard completedProcess.terminationStatus != 0 else { return }
            Task { @MainActor [weak self] in
                self?.onError?("macOS could not put the displays to sleep.")
            }
        }
        do {
            try process.run()
        } catch {
            onError?("The display couldn’t be put to sleep: \(error.localizedDescription)")
        }
    }

    private func openSystemSettingsFallback() {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
            onError?("Open System Settings, then choose Wallpaper → Screen Saver → Other → My Wallpaper.")
            return
        }
        workspace.openApplication(at: url, configuration: workspaceOpenConfiguration()) { [weak self] application, error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.onError?("System Settings could not be opened: \(error.localizedDescription)")
                }
            } else {
                application?.activate(options: [.activateAllWindows])
            }
        }
    }

    private func workspaceOpenConfiguration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = true
        return configuration
    }
}
