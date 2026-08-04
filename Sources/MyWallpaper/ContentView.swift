import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: WallpaperStore
    @State private var selectedScreenID: String?
    @State private var isPickingVideo = false
    @State private var selectedSection = SidebarSection.displays

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x171A24), Color(hex: 0x0B0C12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                mainContent
            }
        }
        .fileImporter(
            isPresented: $isPickingVideo,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result, let selectedScreenID else { return }
            Task { await store.importVideos(from: urls, for: selectedScreenID) }
        }
        .onAppear {
            store.refreshScreens()
            if selectedScreenID == nil {
                selectScreen(store.availableScreens.first?.id)
            }
        }
        .alert(
            "My Wallpaper needs attention",
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
            HStack(spacing: 11) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                Text("My Wallpaper")
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.bottom, 34)

            SidebarItem(
                title: "Displays",
                icon: "display.2",
                selected: selectedSection == .displays
            ) {
                selectedSection = .displays
            }
            SidebarItem(
                title: "Preferences",
                icon: "slider.horizontal.3",
                selected: selectedSection == .preferences
            ) {
                selectedSection = .preferences
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Label("Runs privately on your Mac", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Your videos never leave this device.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 52)
        .padding(.horizontal, 22)
        .padding(.bottom, 24)
        .frame(width: 236)
        .background(.black.opacity(0.18))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedSection {
        case .displays:
            displaysContent
        case .preferences:
            preferencesContent
        }
    }

    private var displaysContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Screensaver studio")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Give every display its own video or looping playlist.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: store.statusText, active: store.isScreenSaverInstalled)
                }

                displayPicker

                if let selectedScreenID {
                    preview(for: selectedScreenID)
                    playlistCard(for: selectedScreenID)
                } else {
                    ContentUnavailableView(
                        "No displays detected",
                        systemImage: "display.trianglebadge.exclamationmark",
                        description: Text("Reconnect a display, then reopen My Wallpaper.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .padding(.top, 50)
            .padding(.horizontal, 34)
            .padding(.bottom, 34)
        }
    }

    private var preferencesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preferences")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Connect My Wallpaper to macOS and tune playback.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(
                        text: store.isScreenSaverInstalled ? "Screen saver installed" : "Installation required",
                        active: store.isScreenSaverInstalled
                    )
                }

                NativeGlassSection {
                    HStack(spacing: 22) {
                        Image(systemName: store.isScreenSaverInstalled
                              ? "checkmark.shield.fill"
                              : "rectangle.and.arrow.down")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(store.isScreenSaverInstalled ? .green : Color.accentPurple)
                            .frame(width: 62, height: 62)
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Native macOS screen saver")
                                .font(.system(size: 18, weight: .semibold))
                            Text(store.isScreenSaverInstalled
                                 ? "Installed and ready to be selected in System Settings."
                                 : "Install the system module so macOS controls activation and secure locking.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 16)

                        VStack(alignment: .trailing, spacing: 9) {
                            Button(store.isScreenSaverInstalled ? "Reinstall" : "Install Screen Saver") {
                                store.installScreenSaver()
                            }
                            .buttonStyle(PrimaryButtonStyle(compact: true))

                            Button("Open System Settings") {
                                store.openScreenSaverSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(26)
                }
                .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 16) {
                    playbackCard
                    privacyCard
                }

                Text("After selecting My Wallpaper, configure the password delay in System Settings → Lock Screen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 50)
            .padding(.horizontal, 34)
            .padding(.bottom, 34)
        }
    }

    private var displayPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(store.availableScreens) { screen in
                    let configuration = store.configuration(for: screen.id)
                    let videoCount = store.videos(for: screen.id).count
                    Button {
                        selectScreen(screen.id)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: screen.id == selectedScreenID ? "display" : "rectangle.on.rectangle")
                                .font(.system(size: 17, weight: .medium))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(screen.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(videoCount == 0
                                     ? "Not configured"
                                     : "\(configuration.mode.rawValue) · \(videoCount) video\(videoCount == 1 ? "" : "s")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minWidth: 180, minHeight: 54, alignment: .leading)
                        .background(
                            screen.id == selectedScreenID ? Color.accentPurple.opacity(0.22) : Color.white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(screen.id == selectedScreenID ? Color.accentPurple : Color.white.opacity(0.07))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func preview(for screenID: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.45))

            if let player = store.previewPlayer {
                PlayerPreviewView(player: player, scaling: store.settings.scaling)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
                    .overlay(alignment: .bottomLeading) {
                        videoCaption(for: screenID)
                    }
            } else {
                VStack(spacing: 17) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.white.opacity(0.65))
                    VStack(spacing: 5) {
                        Text("Choose a video for this display")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Select one video now, or switch to Playlist below.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Button("Choose Video…") { isPickingVideo = true }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }

            if store.isImporting {
                ZStack {
                    Color.black.opacity(0.72)
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Preparing your videos…")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }
        }
        .aspectRatio(16 / 8.6, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 15)
    }

    private func videoCaption(for screenID: String) -> some View {
        let configuration = store.configuration(for: screenID)
        let videos = store.videos(for: screenID)
        let startVideo = videos.first { $0.id == configuration.startVideoID } ?? videos.first

        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(startVideo?.displayName ?? "Selected video")
                    .font(.system(size: 14, weight: .semibold))
                Text(configuration.mode == .playlist
                     ? "Starts here, then loops \(videos.count) videos"
                     : "Loops continuously")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Preview all displays") { store.screenSaver.previewFullScreen() }
                .buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .padding(18)
        .background(.ultraThinMaterial)
    }

    private func playlistCard(for screenID: String) -> some View {
        let configuration = store.configuration(for: screenID)
        let videos = store.videos(for: screenID)

        return SettingsCard(title: "Content for \(configuration.screenName)", icon: "rectangle.stack.fill") {
            VStack(spacing: 16) {
                HStack {
                    Picker("Playback type", selection: Binding(
                        get: { store.configuration(for: screenID).mode },
                        set: { store.setMode($0, for: screenID) }
                    )) {
                        ForEach(PlaybackMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)

                    Spacer()

                    Button(configuration.mode == .single ? "Choose Video…" : "Add Videos…") {
                        isPickingVideo = true
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                }

                if videos.isEmpty {
                    Text("No videos assigned to this display yet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
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
                                Divider().overlay(.white.opacity(0.06))
                            }
                        }
                    }
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                }

                if configuration.mode == .playlist, !videos.isEmpty {
                    Label(
                        "The Start badge marks the first video. The playlist continues in order and loops forever.",
                        systemImage: "repeat"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var playbackCard: some View {
        SettingsCard(title: "Playback", icon: "play.fill") {
            VStack(spacing: 18) {
                HStack {
                    Text("Video sizing")
                    Spacer()
                    Picker("Video sizing", selection: Binding(
                        get: { store.settings.scaling },
                        set: { store.setScaling($0) }
                    )) {
                        ForEach(VideoScaling.allCases) { scaling in
                            Text(scaling.rawValue).tag(scaling)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                Divider().overlay(.white.opacity(0.06))

                Toggle("Mute audio", isOn: Binding(
                    get: { store.settings.isMuted },
                    set: { store.setMuted($0) }
                ))
                .toggleStyle(.switch)
            }
            .font(.system(size: 13))
        }
        .frame(maxWidth: .infinity)
    }

    private var privacyCard: some View {
        SettingsCard(title: "Privacy", icon: "hand.raised.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Label("Videos stay on this Mac", systemImage: "internaldrive.fill")
                Label("No account or upload required", systemImage: "person.crop.circle.badge.checkmark")
                Label("macOS handles secure locking", systemImage: "lock.fill")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func selectScreen(_ screenID: String?) {
        selectedScreenID = screenID
        store.selectScreen(screenID)
    }
}

private enum SidebarSection {
    case displays
    case preferences
}

private struct PlayerPreviewView: NSViewRepresentable {
    let player: AVPlayer
    let scaling: VideoScaling

    func makeNSView(context: Context) -> PlayerPreviewNSView {
        PlayerPreviewNSView(player: player, scaling: scaling)
    }

    func updateNSView(_ nsView: PlayerPreviewNSView, context: Context) {
        nsView.update(player: player, scaling: scaling)
    }
}

private final class PlayerPreviewNSView: NSView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer, scaling: VideoScaling) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
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
        playerLayer.player = player
        playerLayer.videoGravity = scaling == .fill ? .resizeAspectFill : .resizeAspect
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
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Image(systemName: "film.fill")
                .foregroundStyle(Color.accentPurple)
            Text(video.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer()

            Button {
                setAsStart()
            } label: {
                Label(isStartVideo ? "Start" : "Start here", systemImage: isStartVideo ? "flag.fill" : "flag")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isStartVideo ? Color.accentPurple : .secondary)

            if allowsReordering {
                Button(action: moveUp) { Image(systemName: "chevron.up") }
                    .disabled(!canMoveUp)
                Button(action: moveDown) { Image(systemName: "chevron.down") }
                    .disabled(!canMoveDown)
            }
            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
    }
}

private struct SidebarItem: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .white : .secondary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(
                    selected
                        ? Color.white.opacity(0.09)
                        : Color.white.opacity(isHovering ? 0.045 : 0),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
    }
}

private struct NativeGlassSection<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NativeGlassHostingView<Content> {
        NativeGlassHostingView(rootView: content)
    }

    func updateNSView(_ nsView: NativeGlassHostingView<Content>, context: Context) {
        nsView.update(rootView: content)
    }
}

private final class NativeGlassHostingView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>

    init(rootView: Content) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)

        let effectView = makeEffectView(containing: hostingView)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        hostingView.fittingSize
    }

    func update(rootView: Content) {
        hostingView.rootView = rootView
        invalidateIntrinsicContentSize()
    }

    private func makeEffectView(containing contentView: NSView) -> NSView {
        if #available(macOS 26.0, *),
           let glassClass = NSClassFromString("NSGlassEffectView") as? NSObject.Type,
           let glassView = glassClass.init() as? NSView {
            let glassObject = glassView as NSObject
            glassObject.setValue(contentView, forKey: "contentView")
            glassObject.setValue(NSNumber(value: 24.0), forKey: "cornerRadius")
            glassObject.setValue(
                NSColor.controlAccentColor.withAlphaComponent(0.12),
                forKey: "tintColor"
            )
            glassObject.setValue(NSNumber(value: 0), forKey: "style")
            return glassView
        }

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 24
        visualEffectView.layer?.masksToBounds = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])
        return visualEffectView
    }
}

private struct StatusPill: View {
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(active ? Color.green : Color.white.opacity(0.4))
                .frame(width: 7, height: 7)
                .shadow(color: active ? .green : .clear, radius: 4)
            Text(text)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.08)) }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            content
        }
        .padding(20)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07)) }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 6 : 9)
            .background(
                Color.accentPurple.opacity(configuration.isPressed ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: compact ? 7 : 9)
            )
    }
}

private extension Color {
    static let accentPurple = Color(hex: 0x7B61FF)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct SettingsView: View {
    @ObservedObject var store: WallpaperStore

    var body: some View {
        Form {
            Section("System Screen Saver") {
                LabeledContent("Status") {
                    Text(store.isScreenSaverInstalled ? "Installed" : "Not installed")
                }
                Button(store.isScreenSaverInstalled ? "Reinstall Screen Saver" : "Install Screen Saver") {
                    store.installScreenSaver()
                }
                Button("Open Screen Saver Settings") {
                    store.openScreenSaverSettings()
                }
            }
            Section("Playback") {
                Toggle("Mute audio", isOn: Binding(
                    get: { store.settings.isMuted },
                    set: { store.setMuted($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
