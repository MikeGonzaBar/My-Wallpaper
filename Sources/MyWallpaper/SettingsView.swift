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

            ScreenSaverSetupPanel(store: store)

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
