import SwiftUI

struct PreferencesDashboardView: View {
    @ObservedObject var store: WallpaperStore
    let motionDirection: RetroVerticalMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RetroPageHeader(
                    code: "SYS/02",
                    title: "PREFERENCES",
                    subtitle: "SYSTEM INTEGRATION, PLAYBACK, AND PRIVACY CONTROLS."
                ) {
                    RetroStatusBadge(text: store.statusText, active: store.isScreenSaverReady)
                }
                .retroStaggeredEntrance(index: 0, direction: motionDirection)

                ScreenSaverSetupPanel(store: store)
                    .retroStaggeredEntrance(index: 1, direction: motionDirection)

                appearanceWindow
                    .retroStaggeredEntrance(index: 2, direction: motionDirection)

                LaunchAtLoginPanel(controller: store.launchAtLogin)
                    .retroStaggeredEntrance(index: 3, direction: motionDirection)

                PerformanceModePanel(store: store)
                    .retroStaggeredEntrance(index: 4, direction: motionDirection)

                HStack(alignment: .top, spacing: 16) {
                    playbackWindow
                    privacyWindow
                }
                .retroStaggeredEntrance(index: 5, direction: motionDirection)

                Text("NOTE: SET THE PASSWORD DELAY IN SYSTEM SETTINGS → LOCK SCREEN.")
                    .font(RetroFont.label(size: 9))
                    .foregroundStyle(RetroPalette.secondaryInk)
                    .retroStaggeredEntrance(index: 6, direction: motionDirection)
            }
            .padding(24)
        }
        .background(RetroPalette.desktop)
    }

    private var playbackWindow: some View {
        RetroWindow(title: "PLAYBACK") {
            VStack(alignment: .leading, spacing: 18) {
                Text("VIDEO SIZING")
                    .font(RetroFont.label(size: 10))

                RetroChoiceBar(
                    values: VideoScaling.allCases,
                    selected: store.settings.scaling,
                    accessibilityLabel: "Video sizing",
                    title: { $0.title.uppercased() },
                    accessibilityTitle: { $0.title },
                    onSelect: store.setScaling
                )

                RetroDivider()

                RetroCheckbox(
                    title: "MUTE AUDIO",
                    isOn: store.settings.isMuted,
                    action: { store.setMuted(!store.settings.isMuted) }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var appearanceWindow: some View {
        RetroWindow(title: "APPEARANCE") {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LIGHT, DARK, OR FOLLOW MACOS.")
                        .font(RetroFont.label(size: 10))
                    Text("AUTOMATIC IS THE DEFAULT.")
                        .font(RetroFont.body(size: 9))
                        .foregroundStyle(RetroPalette.secondaryInk)
                }
                Spacer()
                AppearanceModePicker(
                    mode: store.appearanceMode,
                    onSelect: store.setAppearanceMode
                )
                .frame(width: 285)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var privacyWindow: some View {
        RetroWindow(title: "PRIVACY") {
            VStack(alignment: .leading, spacing: 12) {
                RetroFact(marker: "■", text: "VIDEOS STAY ON THIS MAC")
                RetroFact(marker: "■", text: "NO ACCOUNT OR UPLOAD")
                RetroFact(marker: "■", text: "macOS HANDLES SECURE LOCKING")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}
