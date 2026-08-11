import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: WallpaperStore
    @State private var selectedScreenID: String?
    @State private var isPickingVideo = false
    @State private var importDestinationScreenID: String?
    @State private var isPreparingImports = false
    @State private var importReviewRequest: ImportReviewRequest?
    @State private var libraryPickerRequest: LibraryPickerRequest?
    @State private var selectedLibraryVideoID: String?
    @State private var isPreviewReady = false
    @State private var hasPreviewLoadingMinimumElapsed = false
    @State private var selectedSection = SidebarSection.displays
    @State private var pageMotionDirection = RetroVerticalMotion.up
    @State private var displayMotionDirection = RetroHorizontalMotion.left

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(RetroPalette.ink)
                .frame(width: 1)
            mainContent
        }
        .background(RetroPalette.desktop)
        .foregroundStyle(RetroPalette.ink)
        .environment(\.font, RetroFont.body())
        .fileImporter(
            isPresented: $isPickingVideo,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result, !urls.isEmpty else { return }
            Task {
                isPreparingImports = true
                let candidates = await store.prepareVideoImports(from: urls)
                isPreparingImports = false
                if !candidates.isEmpty {
                    importReviewRequest = ImportReviewRequest(
                        candidates: candidates,
                        destinationScreenID: importDestinationScreenID
                    )
                }
            }
        }
        .sheet(item: $libraryPickerRequest) { request in
            AddFromLibrarySheet(
                store: store,
                screenID: request.screenID,
                initialVideoID: request.initialVideoID,
                onImportNew: { beginImport(destinationScreenID: request.screenID) },
                onDismiss: { libraryPickerRequest = nil }
            )
        }
        .sheet(item: $importReviewRequest) { request in
            ImportVideosReviewSheet(
                store: store,
                candidates: request.candidates,
                destinationScreenID: request.destinationScreenID,
                onChooseMore: {
                    importReviewRequest = nil
                    DispatchQueue.main.async {
                        beginImport(destinationScreenID: request.destinationScreenID)
                    }
                },
                onComplete: { selectedVideoID in
                    if request.destinationScreenID == nil {
                        selectedLibraryVideoID = selectedVideoID
                        selectSection(.library)
                    }
                    importReviewRequest = nil
                    importDestinationScreenID = nil
                },
                onDismiss: {
                    importReviewRequest = nil
                    importDestinationScreenID = nil
                }
            )
        }
        .overlay {
            if isPreparingImports {
                ZStack {
                    DitherPattern(opacity: 0.84)
                    Text("ANALYZING VIDEO CONTENT…")
                        .font(RetroFont.label(size: 10))
                        .padding(14)
                        .background(RetroPalette.paper)
                        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
                }
            }
        }
        .onAppear {
            store.refreshScreens()
            reconcileSelectedScreen(with: store.availableScreens)
            store.setDisplaysPageVisible(selectedSection == .displays)
        }
        .onDisappear { store.setDisplaysPageVisible(false) }
        .onChange(of: selectedSection) { _, section in
            store.setDisplaysPageVisible(section == .displays)
        }
        .onChange(of: store.availableScreens) { _, screens in
            reconcileSelectedScreen(with: screens)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMyWallpaperScreenSaverSetup)) { _ in
            selectSection(.preferences)
        }
        .alert(
            "MY WALLPAPER NEEDS ATTENTION",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { store.clearError() }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }

    private var sidebar: some View {
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

            RetroNavigationItem(
                marker: "01",
                title: "DISPLAYS",
                selected: selectedSection == .displays
            ) {
                selectSection(.displays)
            }

            RetroNavigationItem(
                marker: "02",
                title: "VIDEO LIBRARY",
                selected: selectedSection == .library
            ) {
                selectSection(.library)
            }

            RetroNavigationItem(
                marker: "03",
                title: "PREFERENCES",
                selected: selectedSection == .preferences
            ) {
                selectSection(.preferences)
            }

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

    private var mainContent: some View {
        ZStack(alignment: .topLeading) {
            Group {
                switch selectedSection {
                case .displays:
                    displaysContent
                case .library:
                    VideoLibraryView(
                        store: store,
                        selectedVideoID: $selectedLibraryVideoID,
                        onImport: { beginImport(destinationScreenID: nil) },
                        onAddToDisplay: { video in
                            guard let screenID = selectedScreenID ?? store.availableScreens.first?.id else {
                                return
                            }
                            showLibraryPicker(for: screenID, initialVideoID: video.id)
                        }
                    )
                case .preferences:
                    preferencesContent
                }
            }
            .id(selectedSection)
            .transition(reduceMotion ? .opacity : .retroVertical(pageMotionDirection))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var displaysContent: some View {
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
                        .transition(
                            reduceMotion ? .opacity : .retroHorizontal(displayMotionDirection)
                        )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
                .retroStaggeredEntrance(index: 2, direction: pageMotionDirection)
            }
            .padding(24)
        }
        .background(RetroPalette.desktop)
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

    private var preferencesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RetroPageHeader(
                    code: "SYS/02",
                    title: "PREFERENCES",
                    subtitle: "SYSTEM INTEGRATION, PLAYBACK, AND PRIVACY CONTROLS."
                ) {
                    RetroStatusBadge(
                        text: store.statusText,
                        active: store.isScreenSaverReady
                    )
                }
                .retroStaggeredEntrance(index: 0, direction: pageMotionDirection)

                ScreenSaverSetupPanel(store: store)
                .retroStaggeredEntrance(index: 1, direction: pageMotionDirection)

                appearanceWindow
                    .retroStaggeredEntrance(index: 2, direction: pageMotionDirection)

                LaunchAtLoginPanel(controller: store.launchAtLogin)
                    .retroStaggeredEntrance(index: 3, direction: pageMotionDirection)

                PerformanceModePanel(store: store)
                    .retroStaggeredEntrance(index: 4, direction: pageMotionDirection)

                HStack(alignment: .top, spacing: 16) {
                    playbackWindow
                    privacyWindow
                }
                .retroStaggeredEntrance(index: 5, direction: pageMotionDirection)

                Text("NOTE: SET THE PASSWORD DELAY IN SYSTEM SETTINGS → LOCK SCREEN.")
                    .font(RetroFont.label(size: 9))
                    .foregroundStyle(RetroPalette.secondaryInk)
                    .retroStaggeredEntrance(index: 6, direction: pageMotionDirection)
            }
            .padding(24)
        }
        .background(RetroPalette.desktop)
    }

    private var displayPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(store.availableScreens.enumerated()), id: \.element.id) { index, screen in
                    let configuration = store.configuration(for: screen.id)
                    let videoCount = store.videos(for: screen.id).count
                    let isSelected = screen.id == selectedScreenID
                    let usesFallback = store.usesFallbackPlayback(for: screen.id)
                    Button {
                        selectScreen(screen.id)
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
                            Text(usesFallback
                                 ? "USING FALLBACK PLAYLIST"
                                 : videoCount == 0
                                    ? "NO SIGNAL"
                                    : "\(configuration.mode.rawValue.uppercased()) / \(videoCount) VIDEO\(videoCount == 1 ? "" : "S")")
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
                    .focusable(false)
                    .focusEffectDisabled()
                    .retroHoverEffect()
                    .animation(RetroMotion.selection, value: isSelected)
                }
            }
            .padding(.bottom, 3)
        }
        .scrollIndicators(.hidden)
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
                VStack(spacing: 16) {
                    Text("▶")
                        .font(RetroFont.headline(size: 40))
                        .foregroundStyle(RetroPalette.paper)
                    Text("NO VIDEO SIGNAL")
                        .font(RetroFont.headline(size: 18))
                        .foregroundStyle(RetroPalette.paper)
                    Text("CHOOSE ONE VIDEO OR SWITCH TO PLAYLIST MODE.")
                        .font(RetroFont.body(size: 10))
                        .foregroundStyle(RetroPalette.surfaceHighest)
                    Button("CHOOSE FROM LIBRARY…") {
                        showLibraryPicker(for: screenID)
                    }
                        .buttonStyle(RetroButtonStyle(primary: true))
                }
            }

            if store.isImporting {
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
        }
        .aspectRatio(16 / 8.6, contentMode: .fit)
        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
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
                HStack(spacing: 12) {
                    Text("PLAYBACK TYPE")
                        .font(RetroFont.label(size: 10))

                    RetroChoiceBar(
                        values: PlaybackMode.allCases,
                        selected: configuration.mode,
                        title: { $0.rawValue.uppercased() },
                        onSelect: { store.setMode($0, for: screenID) }
                    )
                    .frame(maxWidth: 320)

                    Spacer()

                    Button(configuration.mode == .single ? "CHOOSE FROM LIBRARY…" : "ADD FROM LIBRARY…") {
                        showLibraryPicker(for: screenID)
                    }
                    .buttonStyle(RetroButtonStyle(primary: true, compact: true))

                    Button("IMPORT NEW…") {
                        beginImport(destinationScreenID: screenID)
                    }
                    .buttonStyle(RetroButtonStyle(compact: true))
                }

                if videos.isEmpty {
                    Text("[ NO VIDEOS ASSIGNED FROM THE LIBRARY ]")
                        .font(RetroFont.body(size: 11))
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            PlaylistRow(
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

                if configuration.mode == .playlist, !videos.isEmpty {
                    Text("↻ START MARKS THE FIRST FILE. THE LIST CONTINUES IN ORDER AND LOOPS FOREVER.")
                        .font(RetroFont.body(size: 9))
                        .foregroundStyle(RetroPalette.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var playbackWindow: some View {
        RetroWindow(title: "PLAYBACK") {
            VStack(alignment: .leading, spacing: 18) {
                Text("VIDEO SIZING")
                    .font(RetroFont.label(size: 10))

                RetroChoiceBar(
                    values: VideoScaling.allCases,
                    selected: store.settings.scaling,
                    title: { $0.rawValue.uppercased() },
                    onSelect: { store.setScaling($0) }
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

    private func selectScreen(_ screenID: String?) {
        guard screenID != selectedScreenID else { return }

        let currentIndex = store.availableScreens.firstIndex { $0.id == selectedScreenID }
        let newIndex = store.availableScreens.firstIndex { $0.id == screenID }
        if let currentIndex, let newIndex {
            displayMotionDirection = .direction(from: currentIndex, to: newIndex)
        }

        let shouldAnimate = selectedScreenID != nil && screenID != nil
        if shouldAnimate && !reduceMotion {
            withAnimation(RetroMotion.panel) {
                applyScreenSelection(screenID)
            }
        } else {
            applyScreenSelection(screenID)
        }
    }

    private func applyScreenSelection(_ screenID: String?) {
        isPreviewReady = false
        hasPreviewLoadingMinimumElapsed = false
        selectedScreenID = screenID
        store.selectScreen(screenID)
    }

    private func reconcileSelectedScreen(with screens: [DisplayInfo]) {
        guard !screens.contains(where: { $0.id == selectedScreenID }) else { return }
        selectScreen(screens.first?.id)
    }

    private func selectSection(_ section: SidebarSection) {
        guard section != selectedSection else { return }

        pageMotionDirection = section.rawValue > selectedSection.rawValue ? .up : .down
        withAnimation(reduceMotion ? .linear(duration: 0.01) : RetroMotion.panel) {
            selectedSection = section
        }
    }

    private func showLibraryPicker(for screenID: String, initialVideoID: String? = nil) {
        libraryPickerRequest = LibraryPickerRequest(
            screenID: screenID,
            initialVideoID: initialVideoID
        )
    }

    private func beginImport(destinationScreenID: String?) {
        importDestinationScreenID = destinationScreenID
        isPickingVideo = true
    }
}

private enum SidebarSection: Int {
    case displays
    case library
    case preferences
}

private struct LibraryPickerRequest: Identifiable {
    let id = UUID()
    let screenID: String
    let initialVideoID: String?
}

private struct ImportReviewRequest: Identifiable {
    let id = UUID()
    let candidates: [VideoImportCandidate]
    let destinationScreenID: String?
}

private struct PlayerPreviewView: NSViewRepresentable {
    let player: AVPlayer
    let scaling: VideoScaling
    @Binding var isReadyForDisplay: Bool

    func makeNSView(context: Context) -> PlayerPreviewNSView {
        let view = PlayerPreviewNSView(player: player, scaling: scaling)
        configureReadinessHandler(for: view)
        return view
    }

    func updateNSView(_ nsView: PlayerPreviewNSView, context: Context) {
        configureReadinessHandler(for: nsView)
        nsView.update(player: player, scaling: scaling)
    }

    private func configureReadinessHandler(for view: PlayerPreviewNSView) {
        view.onReadyForDisplayChange = { ready in
            if isReadyForDisplay != ready {
                isReadyForDisplay = ready
            }
        }
    }
}

private final class PlayerPreviewNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var readinessObservation: NSKeyValueObservation?
    var onReadyForDisplayChange: ((Bool) -> Void)? {
        didSet { reportReadiness(playerLayer.isReadyForDisplay) }
    }

    init(player: AVPlayer, scaling: VideoScaling) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        readinessObservation = playerLayer.observe(
            \.isReadyForDisplay,
            options: [.initial, .new]
        ) { [weak self] layer, _ in
            self?.reportReadiness(layer.isReadyForDisplay)
        }
        update(player: player, scaling: scaling)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func update(player: AVPlayer, scaling: VideoScaling) {
        if playerLayer.player !== player {
            reportReadiness(false)
            playerLayer.player = player
        }
        playerLayer.videoGravity = scaling == .fill ? .resizeAspectFill : .resizeAspect
    }

    private func reportReadiness(_ ready: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onReadyForDisplayChange?(ready)
        }
    }
}

private struct PreviewLoadingTip: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("LOADING VIDEO…")
                .font(RetroFont.label(size: 11))
            Text("FIRST FRAME MAY TAKE 1–2 SECONDS.")
                .font(RetroFont.body(size: 9))
                .foregroundStyle(RetroPalette.secondaryInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RetroPalette.paper)
        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
        .background {
            Rectangle()
                .fill(RetroPalette.ink)
                .offset(x: 3, y: 3)
        }
        .padding(.trailing, 3)
        .padding(.bottom, 3)
        .accessibilityElement(children: .combine)
    }
}

private struct PlaylistRow: View {
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
            .retroHoverEffect()

            if allowsReordering {
                RetroRowButton(title: "↑", disabled: !canMoveUp, action: moveUp)
                RetroRowButton(title: "↓", disabled: !canMoveDown, action: moveDown)
            }

            RetroRowButton(title: "×", action: remove)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 40)
        .background(isStartVideo ? RetroPalette.surfaceHighest : RetroPalette.paper)
    }
}

private struct RetroRowButton: View {
    let title: String
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
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .retroHoverEffect()
    }
}
