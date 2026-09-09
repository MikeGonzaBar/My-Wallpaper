import SwiftUI

struct DisplaysDashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: WallpaperStore
    let selectedScreenID: String?
    let pageMotionDirection: RetroVerticalMotion
    let displayMotionDirection: RetroHorizontalMotion
    let onSelectScreen: (String) -> Void
    let onShowLibraryPicker: (String) -> Void
    let onBeginImport: (String) -> Void

    @State private var isPreviewReady = false
    @State private var hasPreviewLoadingMinimumElapsed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RetroPageHeader(
                    code: "SYS/01",
                    title: "DISPLAY CONTROL",
                    subtitle: "ASSIGN LIBRARY VIDEOS TO EACH CONNECTED SCREEN."
                ) {
                    RetroStatusBadge(text: store.statusText, active: store.isScreenSaverReady)
                }
                .retroStaggeredEntrance(index: 0, direction: pageMotionDirection)

                displayPicker
                    .retroStaggeredEntrance(index: 1, direction: pageMotionDirection)

                ZStack(alignment: .topLeading) {
                    selectedDisplayContent
                        .id(selectedScreenID)
                        .transition(reduceMotion ? .opacity : .retroHorizontal(displayMotionDirection))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
                .retroStaggeredEntrance(index: 2, direction: pageMotionDirection)
            }
            .padding(24)
        }
        .background(RetroPalette.desktop)
        .onChange(of: selectedScreenID) {
            isPreviewReady = false
            hasPreviewLoadingMinimumElapsed = false
        }
    }

    @ViewBuilder
    private var selectedDisplayContent: some View {
        if let selectedScreenID {
            VStack(alignment: .leading, spacing: 20) {
                RetroWindow(title: "LIVE PREVIEW // \(store.configuration(for: selectedScreenID).screenName.uppercased())") {
                    preview(for: selectedScreenID)
                }
                .retroStaggeredEntrance(index: 0, direction: displayMotionDirection)

                playlistWindow(for: selectedScreenID)
                    .retroStaggeredEntrance(index: 1, direction: displayMotionDirection)
            }
        } else {
            RetroWindow(title: "NO DISPLAY SIGNAL") {
                VStack(spacing: 16) {
                    Text("[ DISPLAY NOT FOUND ]")
                        .font(RetroFont.headline(size: 20))
                    Text("CONNECT A DISPLAY. THIS LIST REFRESHES AUTOMATICALLY.")
                        .font(RetroFont.body(size: 11))
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            }
            .retroStaggeredEntrance(index: 0, direction: displayMotionDirection)
        }
    }

    private var displayPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(store.availableScreens.enumerated()), id: \.element.id) { index, screen in
                    displayButton(for: screen, index: index)
                }
            }
            .padding(.bottom, 3)
        }
        .scrollIndicators(.visible)
    }

    private func displayButton(for screen: DisplayInfo, index: Int) -> some View {
        let configuration = store.configuration(for: screen.id)
        let videoCount = store.videos(for: screen.id).count
        let isSelected = screen.id == selectedScreenID
        let usesFallback = store.usesFallbackPlayback(for: screen.id)

        return Button {
            onSelectScreen(screen.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(String(format: "%02d", index + 1))
                        .font(RetroFont.label(size: 9))
                    Spacer()
                    Text(isSelected ? "[ACTIVE]" : "[IDLE]")
                        .font(RetroFont.label(size: 8))
                }
                Text(screen.name.uppercased())
                    .font(RetroFont.label(size: 11))
                    .lineLimit(1)
                Text(displayStatus(
                    configuration: configuration,
                    videoCount: videoCount,
                    usesFallback: usesFallback
                ))
                .font(RetroFont.body(size: 9))
                .opacity(0.72)
            }
            .foregroundStyle(isSelected ? RetroPalette.paper : RetroPalette.ink)
            .padding(12)
            .frame(width: 208, height: 76, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? RetroPalette.ink : RetroPalette.paper)
            .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
            .background {
                Rectangle()
                    .fill(RetroPalette.ink)
                    .offset(x: isSelected ? 0 : 3, y: isSelected ? 0 : 3)
            }
            .padding(.trailing, 3)
            .padding(.bottom, 3)
            .offset(x: isSelected ? 3 : 0, y: isSelected ? 3 : 0)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Display \(index + 1), \(screen.name)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(usesFallback
            ? "Uses the fallback playlist"
            : "\(videoCount) assigned video\(videoCount == 1 ? "" : "s")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .retroHoverEffect()
        .animation(RetroMotion.selection, value: isSelected)
    }

    private func displayStatus(
        configuration: ScreenConfiguration,
        videoCount: Int,
        usesFallback: Bool
    ) -> String {
        if usesFallback {
            return "USING FALLBACK PLAYLIST"
        }
        if videoCount == 0 {
            return "NO SIGNAL"
        }
        return "\(configuration.mode.title.uppercased()) / \(videoCount) VIDEO\(videoCount == 1 ? "" : "S")"
    }

    private func preview(for screenID: String) -> some View {
        ZStack {
            Rectangle().fill(RetroPalette.ink)

            if let player = store.previewPlayer {
                PlayerPreviewView(
                    player: player,
                    scaling: store.settings.scaling,
                    isReadyForDisplay: $isPreviewReady
                )
                .onDisappear { player.pause() }
                .task(id: ObjectIdentifier(player)) {
                    hasPreviewLoadingMinimumElapsed = false
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    hasPreviewLoadingMinimumElapsed = true
                }
                .overlay(alignment: .bottom) {
                    videoCaption(for: screenID)
                }

                if !isPreviewReady || !hasPreviewLoadingMinimumElapsed {
                    PreviewLoadingTip()
                        .allowsHitTesting(false)
                }
            } else {
                noVideoSignal(for: screenID)
            }

            if store.isImporting {
                importingOverlay
            }
        }
        .aspectRatio(16 / 8.6, contentMode: .fit)
        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
    }

    private func noVideoSignal(for screenID: String) -> some View {
        VStack(spacing: 16) {
            Text("▶")
                .font(RetroFont.headline(size: 40))
                .foregroundStyle(RetroPalette.paper)
                .accessibilityHidden(true)
            Text("NO VIDEO SIGNAL")
                .font(RetroFont.headline(size: 18))
                .foregroundStyle(RetroPalette.paper)
            Text("CHOOSE ONE VIDEO OR SWITCH TO PLAYLIST MODE.")
                .font(RetroFont.body(size: 10))
                .foregroundStyle(RetroPalette.surfaceHighest)
            Button("CHOOSE FROM LIBRARY…") {
                onShowLibraryPicker(screenID)
            }
            .buttonStyle(RetroButtonStyle(primary: true))
        }
    }

    private var importingOverlay: some View {
        ZStack {
            DitherPattern(opacity: 0.92)
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("IMPORTING VIDEO DATA…")
                    .font(RetroFont.label(size: 10))
                    .padding(8)
                    .background(RetroPalette.paper)
                    .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
            }
        }
    }

    private func videoCaption(for screenID: String) -> some View {
        let configuration = store.configuration(for: screenID)
        let videos = store.videos(for: screenID)
        let startVideo = videos.first { $0.id == configuration.startVideoID } ?? videos.first

        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(startVideo?.displayName.uppercased() ?? "SELECTED VIDEO")
                    .font(RetroFont.label(size: 10))
                    .lineLimit(1)
                Text(configuration.mode == .playlist
                     ? "STARTS HERE / LOOPS \(videos.count) VIDEOS"
                     : "CONTINUOUS LOOP")
                    .font(RetroFont.body(size: 9))
                    .foregroundStyle(RetroPalette.secondaryInk)
            }
            Spacer()
            Button("PREVIEW ALL DISPLAYS") { store.previewAllDisplays() }
                .buttonStyle(RetroButtonStyle(primary: true, compact: true))
        }
        .padding(12)
        .background(RetroPalette.paper)
        .overlay(alignment: .top) { Rectangle().fill(RetroPalette.ink).frame(height: 1) }
    }

    private func playlistWindow(for screenID: String) -> some View {
        let configuration = store.configuration(for: screenID)
        let videos = store.videos(for: screenID)

        return RetroWindow(title: "PLAYLIST // \(configuration.screenName.uppercased())") {
            VStack(spacing: 16) {
                playlistHeader(configuration: configuration, screenID: screenID)

                if videos.isEmpty {
                    Text("[ NO VIDEOS ASSIGNED FROM THE LIBRARY ]")
                        .font(RetroFont.body(size: 11))
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                } else {
                    playlistRows(videos, configuration: configuration, screenID: screenID)
                }

                if configuration.mode == .playlist, !videos.isEmpty {
                    Text("↻ START MARKS THE FIRST FILE. THE LIST CONTINUES IN ORDER AND LOOPS FOREVER.")
                        .font(RetroFont.body(size: 9))
                        .foregroundStyle(RetroPalette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func playlistHeader(
        configuration: ScreenConfiguration,
        screenID: String
    ) -> some View {
        HStack(spacing: 12) {
            Text("PLAYBACK TYPE")
                .font(RetroFont.label(size: 10))

            RetroChoiceBar(
                values: PlaybackMode.allCases,
                selected: configuration.mode,
                accessibilityLabel: "Playback type",
                title: { $0.title.uppercased() },
                accessibilityTitle: { $0.title },
                onSelect: { store.setMode($0, for: screenID) }
            )
            .frame(maxWidth: 320)

            Spacer()

            Button(configuration.mode == .single ? "CHOOSE FROM LIBRARY…" : "ADD FROM LIBRARY…") {
                onShowLibraryPicker(screenID)
            }
            .buttonStyle(RetroButtonStyle(primary: true, compact: true))

            Button("IMPORT NEW…") {
                onBeginImport(screenID)
            }
            .buttonStyle(RetroButtonStyle(compact: true))
        }
    }

    private func playlistRows(
        _ videos: [ManagedVideo],
        configuration: ScreenConfiguration,
        screenID: String
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                DisplayPlaylistRow(
                    video: video,
                    index: index,
                    isStartVideo: video.id == configuration.startVideoID,
                    allowsReordering: configuration.mode == .playlist,
                    canMoveUp: index > 0,
                    canMoveDown: index < videos.count - 1,
                    setAsStart: { store.setStartVideo(video.id, for: screenID) },
                    moveUp: { store.moveVideo(video.id, by: -1, for: screenID) },
                    moveDown: { store.moveVideo(video.id, by: 1, for: screenID) },
                    remove: { store.removeVideo(video.id, from: screenID) }
                )
                if index < videos.count - 1 {
                    Rectangle().fill(RetroPalette.ink).frame(height: 1)
                }
            }
        }
        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
    }
}
