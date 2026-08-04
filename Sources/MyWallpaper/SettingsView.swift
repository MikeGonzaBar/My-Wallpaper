import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: WallpaperStore

    var body: some View {
        VStack(spacing: 16) {
            RetroPageHeader(
                code: "CTRL/SET",
                title: "MY WALLPAPER",
                subtitle: "SYSTEM SCREEN SAVER SETTINGS"
            ) {
                EmptyView()
            }

            RetroWindow(title: "SYSTEM SCREEN SAVER") {
                VStack(alignment: .leading, spacing: 14) {
                    RetroFact(
                        marker: store.isScreenSaverInstalled ? "■" : "□",
                        text: store.isScreenSaverInstalled ? "MODULE INSTALLED" : "MODULE NOT INSTALLED"
                    )
                    HStack(spacing: 12) {
                        Button(store.isScreenSaverInstalled ? "REINSTALL" : "INSTALL") {
                            store.installScreenSaver()
                        }
                        .buttonStyle(RetroButtonStyle(primary: true, compact: true))
                        Button("OPEN SYSTEM SETTINGS") {
                            store.openScreenSaverSettings()
                        }
                        .buttonStyle(RetroButtonStyle(compact: true))
                    }
                }
            }

            RetroWindow(title: "PLAYBACK") {
                RetroCheckbox(
                    title: "MUTE AUDIO",
                    isOn: store.settings.isMuted,
                    action: { store.setMuted(!store.settings.isMuted) }
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RetroPalette.desktop)
        .foregroundStyle(RetroPalette.ink)
        .environment(\.font, RetroFont.body())
    }
}
