import SwiftUI

struct DisplayPlaylistRow: View {
    let video: ManagedVideo
    let index: Int
    let isStartVideo: Bool
    let allowsReordering: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let setAsStart: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", index + 1))
                .font(RetroFont.label(size: 9))
                .frame(width: 28)

            Text("▣")
                .font(RetroFont.label(size: 10))
                .accessibilityHidden(true)

            Text(video.displayName.uppercased())
                .font(RetroFont.body(size: 9))
                .lineLimit(1)

            if video.sourceMetadata?.isDemanding == true {
                Text("⚠ HIGH LOAD")
                    .font(RetroFont.label(size: 8))
            }

            Spacer()

            Button(action: setAsStart) {
                Text(isStartVideo ? "■ START" : "□ START HERE")
                    .font(RetroFont.label(size: 8))
                    .frame(minWidth: 72, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isStartVideo
                    ? "\(video.displayName) is the starting video"
                    : "Start playlist with \(video.displayName)"
            )
            .accessibilityAddTraits(isStartVideo ? .isSelected : [])
            .retroHoverEffect()

            if allowsReordering {
                DisplayPlaylistRowButton(
                    title: "↑",
                    accessibilityLabel: "Move \(video.displayName) up",
                    disabled: !canMoveUp,
                    action: moveUp
                )
                DisplayPlaylistRowButton(
                    title: "↓",
                    accessibilityLabel: "Move \(video.displayName) down",
                    disabled: !canMoveDown,
                    action: moveDown
                )
            }

            DisplayPlaylistRowButton(
                title: "×",
                accessibilityLabel: "Remove \(video.displayName) from this display",
                action: remove
            )
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 40)
        .background(isStartVideo ? RetroPalette.surfaceHighest : RetroPalette.paper)
    }
}

private struct DisplayPlaylistRowButton: View {
    let title: String
    let accessibilityLabel: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(RetroFont.label(size: 10))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .background(disabled ? RetroPalette.surfaceHighest : RetroPalette.paper)
                .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .retroHoverEffect()
    }
}
