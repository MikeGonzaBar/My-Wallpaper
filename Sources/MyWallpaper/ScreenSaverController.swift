import AppKit
import Combine

@MainActor
final class FullScreenPreviewController {
    private var plans: [ScreenPlaybackPlan] = []
    private var fallbackPlan: ScreenPlaybackPlan?
    private var isMuted = true
    private var scaling = VideoScaling.fill
    private var playbackWindows: [NSWindow] = []
    private var playbackViews: [PlaylistPlayerView] = []
    private var localInputMonitor: Any?
    private var inputArmingTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var applicationCancellables: Set<AnyCancellable> = []
    private var workspaceCancellables: Set<AnyCancellable> = []
    private var cursorIsHidden = false
    private var dismissalPolicy = FullScreenPreviewDismissalPolicy()
    private let activityAssertion: PreviewActivityAsserting

    var onError: ((String) -> Void)?
    var onDismiss: (() -> Void)?
    var isPresenting: Bool { !playbackWindows.isEmpty }

    init(activityAssertion: PreviewActivityAsserting = PreviewActivityAssertion()) {
        self.activityAssertion = activityAssertion
        let center = NotificationCenter.default
        center.publisher(for: NSApplication.willTerminateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.dismiss() }
            }
            .store(in: &applicationCancellables)
        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                guard self?.isPresenting == true else { return }
                self?.dismissIfRequired(for: .displayConfigurationChanged)
                self?.onError?("Displays changed. Start Preview All Displays again.")
                }
            }
            .store(in: &applicationCancellables)
        center.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.dismissIfRequired(for: .applicationResignedActive)
                }
            }
            .store(in: &applicationCancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceCenter.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        let event: FullScreenPreviewDismissalEvent = name == NSWorkspace.willSleepNotification
                            ? .systemWillSleep
                            : .sessionResigned
                        self?.dismissIfRequired(for: event)
                    }
                }
                .store(in: &workspaceCancellables)
        }
    }

    deinit {
        MainActor.assumeIsolated { dismiss() }
    }

    func configure(
        plans: [ScreenPlaybackPlan],
        fallbackPlan: ScreenPlaybackPlan?,
        isMuted: Bool,
        scaling: VideoScaling
    ) {
        self.plans = plans
        self.fallbackPlan = fallbackPlan
        self.isMuted = isMuted
        self.scaling = scaling
    }

    @discardableResult
    func previewAllDisplays() -> Bool {
        guard !isPresenting else { return false }
        guard let fallbackPlan else {
            onError?("Choose at least one readable video before starting Preview All Displays.")
            return false
        }

        var pendingWindows: [NSWindow] = []
        var pendingViews: [PlaylistPlayerView] = []
        for screen in NSScreen.screens {
            let screenID = DisplayIdentifier.stableID(for: screen)
            let plan = plans.first(where: { $0.screenID == screenID }) ?? fallbackPlan
            let view = PlaylistPlayerView(
                videoURLs: plan.orderedVideoURLs,
                isMuted: isMuted,
                scaling: scaling,
                onExit: { [weak self] in self?.dismiss() }
            )
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
            window.contentView = view
            window.setFrame(screen.frame, display: false)
            pendingViews.append(view)
            pendingWindows.append(window)
        }

        guard !pendingWindows.isEmpty else {
            onError?("No connected displays are available for preview.")
            return false
        }
        guard activityAssertion.acquire() else {
            pendingViews.forEach { $0.stop() }
            onError?("macOS could not keep the display awake for preview. Try again.")
            return false
        }

        playbackWindows = pendingWindows
        playbackViews = pendingViews
        dismissalPolicy.activate()
        playbackWindows.forEach { $0.orderFrontRegardless() }
        playbackViews.forEach { $0.play() }
        NSApp.activate(ignoringOtherApps: true)
        playbackWindows.first?.makeKeyAndOrderFront(nil)
        NSCursor.hide()
        cursorIsHidden = true

        inputArmingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.dismissalPolicy.armInput()
            self?.armInputMonitors()
            self?.inputArmingTask = nil
        }
        countdownTask = Task { @MainActor [weak self] in
            for remaining in stride(from: 45, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                self?.playbackViews.forEach { $0.updateCountdown(secondsRemaining: remaining) }
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            self?.dismissIfRequired(for: .timeout)
        }
        return true
    }

    func dismiss() {
        let wasPresenting = isPresenting
        inputArmingTask?.cancel()
        inputArmingTask = nil
        countdownTask?.cancel()
        countdownTask = nil

        if let localInputMonitor {
            NSEvent.removeMonitor(localInputMonitor)
            self.localInputMonitor = nil
        }

        playbackViews.forEach { $0.stop() }
        playbackWindows.forEach { $0.orderOut(nil) }
        playbackViews.removeAll()
        playbackWindows.removeAll()
        dismissalPolicy.deactivate()
        activityAssertion.release()
        if cursorIsHidden {
            NSCursor.unhide()
            cursorIsHidden = false
        }
        if wasPresenting {
            onDismiss?()
        }
    }

    private func armInputMonitors() {
        guard isPresenting, localInputMonitor == nil else { return }
        let exitEvents: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel
        ]
        localInputMonitor = NSEvent.addLocalMonitorForEvents(matching: exitEvents) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissIfRequired(for: .localInput)
            }
            return nil
        }
    }

    private func dismissIfRequired(for event: FullScreenPreviewDismissalEvent) {
        guard dismissalPolicy.shouldDismiss(for: event) else { return }
        dismiss()
    }
}

private final class PlaybackWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
