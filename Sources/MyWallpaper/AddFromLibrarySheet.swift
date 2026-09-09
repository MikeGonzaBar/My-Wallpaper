import SwiftUI

struct AddFromLibrarySheet: View {
    @ObservedObject var store: WallpaperStore
    let screenID: String
    let initialVideoID: String?
    let onImportNew: () -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedVideoIDs: Set<String> = []

    init(
        store: WallpaperStore,
        screenID: String,
        initialVideoID: String? = nil,
        onImportNew: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.screenID = screenID
        self.initialVideoID = initialVideoID
        self.onImportNew = onImportNew
        self.onDismiss = onDismiss
        let isAlreadyAssigned = initialVideoID.map {
            store.configuration(for: screenID).videoIDs.contains($0)
        } ?? false
        _selectedVideoIDs = State(
            initialValue: isAlreadyAssigned ? [] : initialVideoID.map { [$0] } ?? []
        )
    }

    private var configuration: ScreenConfiguration {
        store.configuration(for: screenID)
    }

    private var visibleVideos: [ManagedVideo] {
        guard !searchText.isEmpty else { return store.settings.videos }
        return store.settings.videos.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(
                title: "ADD FROM LIBRARY // \(configuration.screenName.uppercased())"
            )

            VStack(spacing: 16) {
                Text("CHOOSE EXISTING VIDEOS FOR THIS \(configuration.mode == .playlist ? "PLAYLIST" : "DISPLAY").")
                    .font(RetroFont.body(size: 10))

                HStack(spacing: 12) {
                    TextField("SEARCH LIBRARY", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(RetroFont.body(size: 10))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }

                    Text("\(selectedVideoIDs.count) SELECTED")
                        .font(RetroFont.label(size: 9))
                        .frame(minWidth: 96)
                }

                if store.settings.videos.isEmpty {
                    Text("[ THE SHARED LIBRARY IS EMPTY ]")
                        .font(RetroFont.body(size: 11))
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleVideos) { video in
                                libraryRow(video)
                                Rectangle().fill(RetroPalette.ink).frame(height: 1)
                            }
                        }
                    }
                    .frame(height: 360)
                    .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
                }

                HStack {
                    Button("CANCEL", action: onDismiss)
                        .buttonStyle(RetroButtonStyle())
                    Spacer()
                    Button("IMPORT NEW…") {
                        onDismiss()
                        DispatchQueue.main.async { onImportNew() }
                    }
                    .buttonStyle(RetroButtonStyle())
                    Button(addButtonTitle) {
                        let orderedIDs = store.settings.videos
                            .filter { selectedVideoIDs.contains($0.id) }
                            .map(\.id)
                        store.assignVideos(orderedIDs, to: screenID)
                        onDismiss()
                    }
                    .buttonStyle(RetroButtonStyle(primary: true))
                    .disabled(selectedVideoIDs.isEmpty)
                }
            }
            .padding(20)
        }
        .frame(width: 760)
        .background(RetroPalette.paper)
        .foregroundStyle(RetroPalette.ink)
        .environment(\.font, RetroFont.body())
    }

    private var addButtonTitle: String {
        configuration.mode == .single
            ? "CHOOSE VIDEO"
            : "ADD \(selectedVideoIDs.count) VIDEO\(selectedVideoIDs.count == 1 ? "" : "S")"
    }

    private func libraryRow(_ video: ManagedVideo) -> some View {
        let isAssigned = configuration.videoIDs.contains(video.id)
        let isSelected = selectedVideoIDs.contains(video.id)
        return Button {
            guard !isAssigned else { return }
            if configuration.mode == .single {
                selectedVideoIDs = [video.id]
            } else if isSelected {
                selectedVideoIDs.remove(video.id)
            } else {
                selectedVideoIDs.insert(video.id)
            }
        } label: {
            HStack(spacing: 12) {
                Text(isAssigned ? "■" : isSelected ? "■" : "□")
                    .font(RetroFont.label(size: 12))
                VideoThumbnailView(videoURL: video.url, width: 104, height: 58)
                VStack(alignment: .leading, spacing: 5) {
                    Text(video.displayName.uppercased())
                        .font(RetroFont.label(size: 10))
                        .lineLimit(1)
                    Text(metadataText(for: video))
                        .font(RetroFont.body(size: 9))
                        .foregroundStyle(RetroPalette.secondaryInk)
                }
                Spacer()
                Text(isAssigned ? "IN PLAYLIST" : statusText(for: video))
                    .font(RetroFont.label(size: 8))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
            .background(isSelected ? RetroPalette.surfaceHighest : RetroPalette.paper)
            .opacity(isAssigned ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isAssigned)
        .accessibilityLabel(video.displayName)
        .accessibilityValue(
            isAssigned ? "Already assigned" : isSelected ? "Selected" : "Not selected"
        )
        .accessibilityHint(isAssigned ? "Already in this display playlist" : "Press Space to select")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func metadataText(for video: ManagedVideo) -> String {
        guard let metadata = video.sourceMetadata else { return "METADATA PENDING" }
        return "\(metadata.width) × \(metadata.height) • \(String(format: "%.2f", metadata.frameRate)) FPS"
    }

    private func statusText(for video: ManagedVideo) -> String {
        if video.optimizedProfile == store.settings.optimizationProfile,
           let path = video.optimizedPath,
           FileManager.default.isReadableFile(atPath: path) {
            return "OPTIMIZED"
        }
        if video.sourceMetadata?.isDemanding == true { return "HIGH LOAD" }
        return "READY"
    }
}
