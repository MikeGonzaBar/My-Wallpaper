import SwiftUI

struct PlaylistEditorView: View {
    @Environment(\.undoManager) private var undoManager
    @ObservedObject var store: WallpaperStore
    let screenID: String
    @State private var selection = Set<String>()

    private var configuration: ScreenConfiguration { store.configuration(for: screenID) }
    private var videos: [ManagedVideo] { store.videos(for: screenID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(selection.count) SELECTED • COMMAND-CLICK OR SHIFT-CLICK TO SELECT MORE")
                    .font(RetroFont.body(size: 8))
                Spacer()
                Button("REMOVE SELECTED") { store.removeVideos(selection, from: screenID) }
                    .buttonStyle(RetroButtonStyle(compact: true))
                    .disabled(selection.isEmpty)
                Button("UNDO") { undoManager?.undo() }
                    .buttonStyle(RetroButtonStyle(compact: true))
                    .disabled(undoManager?.canUndo != true)
                Button("REDO") { undoManager?.redo() }
                    .buttonStyle(RetroButtonStyle(compact: true))
                    .disabled(undoManager?.canRedo != true)
            }
            List(selection: $selection) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    DisplayPlaylistRow(
                        video: video, index: index,
                        isStartVideo: video.id == configuration.startVideoID,
                        isSelected: selection.contains(video.id),
                        allowsReordering: configuration.mode == .playlist,
                        canMoveUp: index > 0, canMoveDown: index < videos.count - 1,
                        setAsStart: { store.setStartVideo(video.id, for: screenID) },
                        moveUp: { store.moveVideo(video.id, by: -1, for: screenID) },
                        moveDown: { store.moveVideo(video.id, by: 1, for: screenID) },
                        remove: { store.removeVideo(video.id, from: screenID) }
                    )
                    .tag(video.id)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .moveDisabled(configuration.mode != .playlist)
                }
                .onMove { offsets, destination in
                    // Visible rows normally match the saved IDs, but ignore stale missing IDs safely.
                    let movingIDs = Set(offsets.compactMap { videos.indices.contains($0) ? videos[$0].id : nil })
                    let savedOffsets = IndexSet(configuration.videoIDs.indices.filter { movingIDs.contains(configuration.videoIDs[$0]) })
                    let beforeID = videos.indices.contains(destination) ? videos[destination].id : nil
                    let savedDestination = beforeID.flatMap { configuration.videoIDs.firstIndex(of: $0) } ?? configuration.videoIDs.count
                    store.moveVideos(from: savedOffsets, to: savedDestination, for: screenID)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(340, max(60, CGFloat(videos.count) * 44)))
            .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
            .onDeleteCommand { store.removeVideos(selection, from: screenID) }
            .accessibilityLabel("Display playlist")
            .accessibilityHint("Select multiple videos to remove them together. Drag playlist rows to reorder, or use each row's move buttons.")
        }
        .onChange(of: configuration.videoIDs) { _, ids in selection.formIntersection(ids) }
        .onChange(of: screenID) { selection.removeAll() }
    }
}
