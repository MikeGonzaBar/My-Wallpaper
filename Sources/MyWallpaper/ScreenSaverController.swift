import AppKit
import AVFoundation

@MainActor
final class ScreenSaverController {
    private var plans: [ScreenPlaybackPlan] = []
    private var isMuted = true
    private var scaling = VideoScaling.fill
    private var playbackWindows: [NSWindow] = []
    private var playbackViews: [PlaylistPlayerView] = []
    private var globalInputMonitor: Any?
    private var localInputMonitor: Any?
    private var inputArmingTask: Task<Void, Never>?
    private var actionAfterDismissal: (() -> Void)?

    var isPresenting: Bool { !playbackWindows.isEmpty }

    func configure(
        plans: [ScreenPlaybackPlan],
        isMuted: Bool,
        scaling: VideoScaling
    ) {
        self.plans = plans
        self.isMuted = isMuted
        self.scaling = scaling
    }

    func previewFullScreen() {
        present()
    }

    func startScreenSaver(actionAfterDismissal: @escaping () -> Void) {
        present(actionAfterDismissal: actionAfterDismissal)
    }

    func dismiss() {
        inputArmingTask?.cancel()
        inputArmingTask = nil
        guard isPresenting else { return }
        let dismissalAction = actionAfterDismissal
        actionAfterDismissal = nil
        if let globalInputMonitor {
            NSEvent.removeMonitor(globalInputMonitor)
            self.globalInputMonitor = nil
        }
        if let localInputMonitor {
            NSEvent.removeMonitor(localInputMonitor)
            self.localInputMonitor = nil
        }
        playbackViews.forEach { $0.stop() }
        playbackWindows.forEach { $0.orderOut(nil) }
        playbackViews.removeAll()
        playbackWindows.removeAll()
        NSCursor.unhide()
        dismissalAction?()
    }

    private func present(actionAfterDismissal: (() -> Void)? = nil) {
        guard !isPresenting else { return }
        self.actionAfterDismissal = actionAfterDismissal

        for screen in NSScreen.screens {
            let screenID = DisplayIdentifier.stableID(for: screen)
            let plan = plans.first(where: { $0.screenID == screenID })
            let window = PlaybackWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.acceptsMouseMovedEvents = true
            if let plan {
                let playerView = PlaylistPlayerView(
                    videoURLs: plan.orderedVideoURLs,
                    isMuted: isMuted,
                    scaling: scaling
                )
                window.contentView = playerView
                playbackViews.append(playerView)
                playerView.play()
            }
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()

            playbackWindows.append(window)
        }

        guard !playbackWindows.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        playbackWindows.first?.makeKeyAndOrderFront(nil)
        NSCursor.hide()

        // Ignore the menu click and its trailing pointer movement before treating
        // new input as an intentional request to dismiss and lock.
        inputArmingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.armInputMonitors()
            self?.inputArmingTask = nil
        }
    }

    private func armInputMonitors() {
        guard isPresenting, globalInputMonitor == nil, localInputMonitor == nil else { return }
        let exitEvents: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel
        ]
        globalInputMonitor = NSEvent.addGlobalMonitorForEvents(matching: exitEvents) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismiss() }
        }
        localInputMonitor = NSEvent.addLocalMonitorForEvents(matching: exitEvents) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismiss() }
            return nil
        }
    }

}

private final class PlaybackWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class PlaylistPlayerView: NSView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private let orderedURLs: [URL]
    private var nextLoopIndex = 0
    private var ownedItems: Set<ObjectIdentifier> = []
    private var endObserver: NSObjectProtocol?

    init(videoURLs: [URL], isMuted: Bool, scaling: VideoScaling) {
        orderedURLs = videoURLs
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = scaling == .fill ? .resizeAspectFill : .resizeAspect
        layer?.addSublayer(playerLayer)
        player.isMuted = isMuted
        orderedURLs.forEach { url in
            let item = AVPlayerItem(url: url)
            ownedItems.insert(ObjectIdentifier(item))
            player.insert(item, after: nil)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.requeueIfOwned(notification.object as? AVPlayerItem)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func play() {
        player.play()
    }

    func stop() {
        player.pause()
        player.removeAllItems()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func requeueIfOwned(_ endedItem: AVPlayerItem?) {
        guard let endedItem, !orderedURLs.isEmpty,
              ownedItems.remove(ObjectIdentifier(endedItem)) != nil else { return }
        let newItem = AVPlayerItem(url: orderedURLs[nextLoopIndex])
        ownedItems.insert(ObjectIdentifier(newItem))
        player.insert(newItem, after: nil)
        nextLoopIndex = (nextLoopIndex + 1) % orderedURLs.count
    }
}
