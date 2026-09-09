import AppKit
import SwiftUI

@main
struct MyWallpaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WallpaperStore()

    var body: some Scene {
        WindowGroup("My Wallpaper", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 1_040, minHeight: 680)
                .preferredColorScheme(store.appearanceMode.colorScheme)
                .overlay { DiagonalAppearanceTransition(trigger: store.appearanceTransitionID) }
                .background {
                    MainWindowObserver(registry: .shared) { isVisible in
                        store.setMainWindowVisible(isVisible)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarMenu(store: store)
        } label: {
            MenuBarIconView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(store: store)
                .frame(minWidth: 520, idealWidth: 620, maxWidth: 820)
                .frame(minHeight: 640, idealHeight: 760, maxHeight: 900)
                .preferredColorScheme(store.appearanceMode.colorScheme)
                .overlay { DiagonalAppearanceTransition(trigger: store.appearanceTransitionID) }
        }
    }
}

private struct MenuBarIconView: View {
    var body: some View {
        Group {
            if let image = MenuBarIcon.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Image(systemName: "play.rectangle")
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel("My Wallpaper")
    }
}

private struct MenuBarMenu: View {
    @ObservedObject var store: WallpaperStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if store.isScreenSaverReady {
            Button {
                Task {
                    let result = await store.startConfiguredScreenSaver()
                    if result != .started {
                        showScreenSaverSetup()
                    }
                }
            } label: {
                Label("Start Screen Saver", systemImage: "play.rectangle.fill")
            }
            .disabled(store.isStartingScreenSaver)
        } else {
            Button {
                showScreenSaverSetup()
            } label: {
                Label("Finish Screen Saver Setup…", systemImage: "exclamationmark.triangle")
            }
        }

        Button {
            store.previewAllDisplays()
        } label: {
            Label("Preview All Displays (45 Seconds)", systemImage: "rectangle.on.rectangle")
        }
        .help(
            "Preview does not lock your Mac. It ends after 45 seconds, or when you "
                + "move the pointer, press a key, click Exit Preview, or switch apps."
        )

        Button {
            store.lockMacNow()
        } label: {
            Label("Sleep Displays", systemImage: "display")
        }
        .help("Authentication after wake follows your macOS Lock Screen password-delay policy.")

        Divider()

        Button {
            showMainWindow()
        } label: {
            Label("Open My Wallpaper", systemImage: "macwindow")
        }

        Button {
            store.openScreenSaverSettings()
        } label: {
            Label("Screen Saver Settings…", systemImage: "gearshape")
        }

        Divider()

        Button("Quit My Wallpaper") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        let registry = MainWindowRegistry.shared
        if !registry.showExistingWindow() {
            registry.prepareToOpenWindow()
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showScreenSaverSetup() {
        showMainWindow()
        NotificationCenter.default.post(name: .showMyWallpaperScreenSaverSetup, object: nil)
    }
}

extension Notification.Name {
    static let showMyWallpaperScreenSaverSetup = Notification.Name(
        "com.prototype.mywallpaper.show-screen-saver-setup"
    )
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var startedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        captureLoginItemLaunch()
        if startedAsLoginItem {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        captureLoginItemLaunch()
        guard startedAsLoginItem else { return }

        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            MainWindowRegistry.shared.requestHiddenWindow()
            NSApp.hide(nil)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard !flag else {
            return true
        }
        let registry = MainWindowRegistry.shared
        guard registry.showExistingWindow() else {
            registry.prepareToOpenWindow()
            return true
        }
        startedAsLoginItem = false
        return false
    }

    func applicationShouldSaveSecureApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    private func captureLoginItemLaunch() {
        startedAsLoginItem = startedAsLoginItem || ApplicationLaunchPolicy.shouldStartHidden(
            for: NSAppleEventManager.shared().currentAppleEvent
        )
    }
}
