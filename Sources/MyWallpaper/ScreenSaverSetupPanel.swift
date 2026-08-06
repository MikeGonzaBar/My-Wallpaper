import SwiftUI

struct ScreenSaverSetupPanel: View {
    @ObservedObject var store: WallpaperStore

    var body: some View {
        RetroWindow(title: "NATIVE SCREEN SAVER") {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        statusSummary
                        Spacer(minLength: 16)
                        actionButtons
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        statusSummary
                        actionButtons
                    }
                }

                RetroDivider()
                Text("SETUP: WALLPAPER → SCREEN SAVER → OTHER → MY WALLPAPER")
                    .font(RetroFont.label(size: 9))
                Text("macOS handles dismissal and authentication. Set the Lock Screen password delay to Immediately for secure locking.")
                    .font(RetroFont.body(size: 9))
                    .foregroundStyle(RetroPalette.secondaryInk)
            }
        }
    }

    private var statusSummary: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                Rectangle().fill(store.isScreenSaverReady ? RetroPalette.ink : RetroPalette.paper)
                Text(store.isScreenSaverReady ? "■" : "□")
                    .font(RetroFont.headline(size: 24))
                    .foregroundStyle(store.isScreenSaverReady ? RetroPalette.paper : RetroPalette.ink)
            }
            .frame(width: 56, height: 56)
            .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }

            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle)
                    .font(RetroFont.headline(size: 17))
                Text(statusDetail)
                    .font(RetroFont.body(size: 10))
                    .foregroundStyle(RetroPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusTitle: String {
        switch store.screenSaverIntegrationState {
        case .moduleUnavailable:
            "INTEGRATION UNAVAILABLE"
        case .notInstalled:
            "MODULE NOT INSTALLED"
        case .updateRequired:
            "UPDATE REQUIRED"
        case .verificationRequired:
            "VERIFY SYSTEM SETUP"
        case .verificationDenied:
            "AUTOMATION PERMISSION REQUIRED"
        case .notSelected:
            "INSTALLED / NOT SELECTED"
        case .ready:
            "MY WALLPAPER SELECTED"
        }
    }

    private var statusDetail: String {
        switch store.screenSaverIntegrationState {
        case let .moduleUnavailable(message):
            message
        case .notInstalled:
            "Install the native module for manual and automatic screen saver activation."
        case .updateRequired:
            "The installed module is older or different from the one in this app."
        case .verificationRequired:
            "Allow a one-time macOS Automation check so the app never starts the wrong saver."
        case .verificationDenied:
            "Enable My Wallpaper under Privacy & Security → Automation, then recheck."
        case let .notSelected(currentName):
            currentName.map { "My Wallpaper is installed, but \($0) is currently selected." }
                ?? "Select My Wallpaper in macOS Screen Saver settings."
        case .ready:
            "Manual and idle activation now use the native My Wallpaper screen saver."
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(alignment: .trailing, spacing: 10) {
            switch store.screenSaverIntegrationState {
            case .notInstalled:
                Button("INSTALL") { store.installOrUpdateScreenSaver() }
                    .buttonStyle(RetroButtonStyle(primary: true, compact: true))
            case .updateRequired:
                Button("UPDATE") { store.installOrUpdateScreenSaver() }
                    .buttonStyle(RetroButtonStyle(primary: true, compact: true))
            case .verificationRequired:
                Button("VERIFY SYSTEM SETUP") {
                    Task { await store.verifySystemScreenSaverSetup(requestConsent: true) }
                }
                .buttonStyle(RetroButtonStyle(primary: true, compact: true))
            case .verificationDenied:
                Button("OPEN AUTOMATION SETTINGS") { store.openAutomationSettings() }
                    .buttonStyle(RetroButtonStyle(primary: true, compact: true))
                Button("RECHECK") {
                    Task { await store.refreshScreenSaverIntegrationState() }
                }
                .buttonStyle(RetroButtonStyle(compact: true))
            case .notSelected:
                Button("OPEN SYSTEM SETTINGS") { store.openScreenSaverSettings() }
                    .buttonStyle(RetroButtonStyle(primary: true, compact: true))
                Button("RECHECK") {
                    Task { await store.refreshScreenSaverIntegrationState() }
                }
                .buttonStyle(RetroButtonStyle(compact: true))
            case .ready:
                Button("REINSTALL") { store.installOrUpdateScreenSaver() }
                    .buttonStyle(RetroButtonStyle(compact: true))
                Button("OPEN SYSTEM SETTINGS") { store.openScreenSaverSettings() }
                    .buttonStyle(RetroButtonStyle(compact: true))
            case .moduleUnavailable:
                Button("RECHECK") {
                    Task { await store.refreshScreenSaverIntegrationState() }
                }
                .buttonStyle(RetroButtonStyle(compact: true))
            }
        }
    }
}
