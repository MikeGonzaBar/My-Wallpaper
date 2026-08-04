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
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarMenu(store: store)
        } label: {
            Label("My Wallpaper", systemImage: "play.rectangle.fill")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(store: store)
                .frame(width: 520)
                .preferredColorScheme(.dark)
        }
    }
}

private struct MenuBarMenu: View {
    @ObservedObject var store: WallpaperStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            store.startConfiguredScreenSaver()
        } label: {
            Label("Start Screen Saver", systemImage: "play.rectangle.fill")
        }

        Button {
            store.lockMacNow()
        } label: {
            Label("Lock Mac Now", systemImage: "lock.fill")
        }

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
        if let window = NSApp.windows.first(where: { $0.title == "My Wallpaper" && !$0.isSheet }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldSaveSecureApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreSecureApplicationState(_ app: NSApplication) -> Bool {
        false
    }
}
