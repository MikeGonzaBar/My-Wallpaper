import AppKit
import SwiftUI

enum SidebarSection: Int {
    case displays
    case library
    case preferences
}

struct WallpaperSidebar: View {
    let selectedSection: SidebarSection
    let onSelect: (SidebarSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }

                Text("MY WALLPAPER")
                    .font(RetroFont.headline(size: 18))
                Text("VIDEO SCREEN SYSTEM")
                    .font(RetroFont.label(size: 9))
                    .foregroundStyle(RetroPalette.secondaryInk)
            }
            .padding(.bottom, 28)

            navigationItem(marker: "01", title: "DISPLAYS", section: .displays)
            navigationItem(marker: "02", title: "VIDEO LIBRARY", section: .library)
            navigationItem(marker: "03", title: "PREFERENCES", section: .preferences)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                RetroDivider()
                Text("LOCAL PROCESS")
                    .font(RetroFont.label(size: 9))
                Text("VIDEOS NEVER LEAVE\nTHIS MACINTOSH.")
                    .font(RetroFont.body(size: 9))
                    .foregroundStyle(RetroPalette.secondaryInk)
                    .lineSpacing(3)
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(width: 216)
        .background(RetroPalette.surfaceDim)
    }

    private func navigationItem(
        marker: String,
        title: String,
        section: SidebarSection
    ) -> some View {
        RetroNavigationItem(
            marker: marker,
            title: title,
            selected: selectedSection == section,
            action: { onSelect(section) }
        )
    }
}
