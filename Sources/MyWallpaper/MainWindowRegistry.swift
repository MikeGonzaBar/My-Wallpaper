import AppKit
import Combine
import SwiftUI

@MainActor
protocol MainWindowControlling: AnyObject {
    var identifier: NSUserInterfaceItemIdentifier? { get set }
    var isEffectivelyVisible: Bool { get }
    func makeKeyAndOrderFront(_ sender: Any?)
    func orderOut(_ sender: Any?)
}

extension NSWindow: MainWindowControlling {
    var isEffectivelyVisible: Bool {
        isVisible && !isMiniaturized && occlusionState.contains(.visible)
    }
}

@MainActor
protocol ApplicationPresenting {
    func prepareToPresentWindow()
    func activate()
}

@MainActor
struct SystemApplicationPresenter: ApplicationPresenting {
    func prepareToPresentWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
    }

    func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class MainWindowRegistry {
    static let shared = MainWindowRegistry()
    static let identifier = NSUserInterfaceItemIdentifier(
        "com.prototype.mywallpaper.window.main"
    )

    private weak var window: (any MainWindowControlling)?
    private let application: any ApplicationPresenting
    private var hidesWindowUponRegistration = false

    convenience init() {
        self.init(application: SystemApplicationPresenter())
    }

    init(application: any ApplicationPresenting) {
        self.application = application
    }

    var isVisible: Bool {
        window?.isEffectivelyVisible == true
    }

    func register(_ window: any MainWindowControlling) {
        window.identifier = Self.identifier
        self.window = window
        if hidesWindowUponRegistration {
            window.orderOut(nil)
        }
    }

    func unregister(_ window: any MainWindowControlling) {
        guard self.window === window else { return }
        self.window = nil
    }

    func prepareToOpenWindow() {
        hidesWindowUponRegistration = false
        application.prepareToPresentWindow()
    }

    @discardableResult
    func showExistingWindow() -> Bool {
        guard let window else { return false }
        prepareToOpenWindow()
        window.makeKeyAndOrderFront(nil)
        application.activate()
        return true
    }

    func requestHiddenWindow() {
        hidesWindowUponRegistration = true
        window?.orderOut(nil)
    }
}

struct MainWindowObserver: NSViewRepresentable {
    let registry: MainWindowRegistry
    let onVisibilityChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> MainWindowObservationView {
        MainWindowObservationView(
            registry: registry,
            onVisibilityChange: onVisibilityChange
        )
    }

    func updateNSView(_ nsView: MainWindowObservationView, context: Context) {
        nsView.onVisibilityChange = onVisibilityChange
        nsView.reportVisibility()
    }

    static func dismantleNSView(_ nsView: MainWindowObservationView, coordinator: ()) {
        nsView.detach()
    }
}

@MainActor
final class MainWindowObservationView: NSView {
    private let registry: MainWindowRegistry
    private weak var observedWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []
    var onVisibilityChange: @MainActor (Bool) -> Void

    init(
        registry: MainWindowRegistry,
        onVisibilityChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.registry = registry
        self.onVisibilityChange = onVisibilityChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard observedWindow !== window else {
            reportVisibility()
            return
        }
        detach()
        guard let window else { return }
        observedWindow = window
        registry.register(window)
        observeVisibility(of: window)
        reportVisibility()
    }

    func detach() {
        cancellables.removeAll()
        if let observedWindow {
            registry.unregister(observedWindow)
        }
        observedWindow = nil
        onVisibilityChange(false)
    }

    func reportVisibility() {
        onVisibilityChange(observedWindow?.isEffectivelyVisible == true)
    }

    private func observeVisibility(of window: NSWindow) {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification
        ]
        for name in names {
            center.publisher(for: name, object: window)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.reportVisibility()
                    }
                }
                .store(in: &cancellables)
        }
    }
}
