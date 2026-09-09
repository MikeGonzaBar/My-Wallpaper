import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: WallpaperStore

    var body: some View {
        ScrollView {
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

                LaunchAtLoginPanel(controller: store.launchAtLogin)

                ScreenSaverSetupPanel(store: store)

                PerformanceModePanel(store: store)

                RetroWindow(title: "PLAYBACK") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("VIDEO SIZING")
                            .font(RetroFont.label(size: 9))
                        RetroChoiceBar(
                            values: VideoScaling.allCases,
                            selected: store.settings.scaling,
                            accessibilityLabel: "Video sizing",
                            title: { $0.title },
                            onSelect: store.setScaling
                        )

                        RetroCheckbox(
                            title: "MUTE AUDIO",
                            isOn: store.settings.isMuted,
                            action: { store.setMuted(!store.settings.isMuted) }
                        )
                    }
                }

                RetroWindow(title: "PRIVACY") {
                    Text("VIDEOS AND SETTINGS STAY ON THIS MAC. MY WALLPAPER DOES NOT USE A NETWORK SERVICE OR ACCOUNT.")
                        .font(RetroFont.body(size: 9))
                        .foregroundStyle(RetroPalette.secondaryInk)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RetroPalette.desktop)
        .foregroundStyle(RetroPalette.ink)
        .environment(\.font, RetroFont.body())
    }
}
