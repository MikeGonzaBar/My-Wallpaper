import AppKit
import SwiftUI

private struct ShowsKeyboardFocusKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var showsKeyboardFocus: Bool {
        get { self[ShowsKeyboardFocusKey.self] }
        set { self[ShowsKeyboardFocusKey.self] = newValue }
    }
}

struct KeyboardNavigationModifier: ViewModifier {
    @State private var showsKeyboardFocus = false

    func body(content: Content) -> some View {
        content
            .environment(\.showsKeyboardFocus, showsKeyboardFocus)
            .focusEffectDisabled(!showsKeyboardFocus)
            .background {
                KeyboardNavigationObserver { showsKeyboardFocus = $0 }
            }
    }
}

private struct KeyboardNavigationObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> KeyboardNavigationObservationView {
        KeyboardNavigationObservationView(onChange: onChange)
    }

    func updateNSView(_ nsView: KeyboardNavigationObservationView, context: Context) {
        nsView.onChange = onChange
    }

    static func dismantleNSView(_ nsView: KeyboardNavigationObservationView, coordinator: ()) {
        nsView.stopObserving()
    }
}

@MainActor
private final class KeyboardNavigationObservationView: NSView {
    var onChange: (Bool) -> Void
    private var eventMonitor: Any?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return }
                if event.type != .keyDown {
                    self.onChange(false)
                } else if event.keyCode == 48,
                          event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                    self.onChange(true)
                }
            }
            return event
        }
    }

    func stopObserving() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }
}
