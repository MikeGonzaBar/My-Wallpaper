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

            RetroWindow(title: "APPEARANCE") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CHOOSE HOW MY WALLPAPER MATCHES YOUR MAC.")
                        .font(RetroFont.body(size: 9))
                        .foregroundStyle(RetroPalette.secondaryInk)
                    AppearanceModePicker(
                        mode: store.appearanceMode,
                        onSelect: store.setAppearanceMode
                    )
                }
            }

            ScreenSaverSetupPanel(store: store)

            PerformanceModePanel(store: store)

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
