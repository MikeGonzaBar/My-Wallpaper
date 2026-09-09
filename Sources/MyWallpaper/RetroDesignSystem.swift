import AppKit
import SwiftUI

enum RetroPalette {
    static let paper = adaptive(light: .white, dark: NSColor(calibratedWhite: 0.10, alpha: 1))
    static let desktop = adaptive(
        light: NSColor(calibratedWhite: 249 / 255, alpha: 1),
        dark: NSColor(calibratedWhite: 0.06, alpha: 1)
    )
    static let surfaceDim = adaptive(
        light: NSColor(calibratedWhite: 232 / 255, alpha: 1),
        dark: NSColor(calibratedWhite: 0.14, alpha: 1)
    )
    static let surfaceHighest = adaptive(
        light: NSColor(calibratedWhite: 226 / 255, alpha: 1),
        dark: NSColor(calibratedWhite: 0.20, alpha: 1)
    )
    static let ink = adaptive(light: .black, dark: NSColor(calibratedWhite: 0.94, alpha: 1))
    static let secondaryInk = adaptive(
        light: NSColor(red: 76 / 255, green: 69 / 255, blue: 70 / 255, alpha: 1),
        dark: NSColor(calibratedWhite: 0.69, alpha: 1)
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

enum RetroFont {
    static func headline(size: CGFloat) -> Font {
        .custom("Helvetica Neue", size: size, relativeTo: .headline).weight(.bold)
    }

    static func body(size: CGFloat = 12) -> Font {
        .custom("Menlo", size: size, relativeTo: .body)
    }

    static func label(size: CGFloat = 11) -> Font {
        .custom("Menlo", size: size, relativeTo: .caption).weight(.bold)
    }
}

enum RetroMotion {
    static let hover = Animation.easeOut(duration: 0.08)
    static let selection = Animation.easeOut(duration: 0.12)
    static let panel = Animation.easeInOut(duration: 0.46)
    static let panelRow = Animation.easeOut(duration: 0.34)
    static let panelRowDelay = 0.09
}

enum RetroVerticalMotion {
    case up
    case down

    var insertionEdge: Edge {
        self == .up ? .bottom : .top
    }

    var removalEdge: Edge {
        self == .up ? .top : .bottom
    }

    var rowOffset: CGSize {
        CGSize(width: 0, height: self == .up ? 72 : -72)
    }
}

enum RetroHorizontalMotion {
    case left
    case right

    static func direction(from currentIndex: Int, to newIndex: Int) -> Self {
        newIndex > currentIndex ? .left : .right
    }

    var insertionEdge: Edge {
        self == .left ? .trailing : .leading
    }

    var removalEdge: Edge {
        self == .left ? .leading : .trailing
    }

    var rowOffset: CGSize {
        CGSize(width: self == .left ? 72 : -72, height: 0)
    }
}

private struct RetroStaggeredEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    let index: Int
    let offset: CGSize
    let animation: Animation
    let delay: Double

    func body(content: Content) -> some View {
        content
            .offset(reduceMotion || isVisible ? .zero : offset)
            .opacity(reduceMotion || isVisible ? 1 : 0)
            .onAppear {
                guard !reduceMotion else {
                    isVisible = true
                    return
                }

                withAnimation(animation.delay(Double(index) * delay)) {
                    isVisible = true
                }
            }
    }
}

private struct RetroHoverEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var shouldLift: Bool {
        isEnabled && isHovering && !reduceMotion
    }

    func body(content: Content) -> some View {
        content
            .offset(y: shouldLift ? -1 : 0)
            .animation(reduceMotion ? nil : RetroMotion.hover, value: shouldLift)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension AnyTransition {
    static func retroVertical(_ direction: RetroVerticalMotion) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: direction.insertionEdge),
            removal: .move(edge: direction.removalEdge)
        )
    }

    static func retroHorizontal(_ direction: RetroHorizontalMotion) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: direction.insertionEdge),
            removal: .move(edge: direction.removalEdge)
        )
    }
}

extension View {
    func retroStaggeredEntrance(index: Int, direction: RetroVerticalMotion) -> some View {
        modifier(RetroStaggeredEntrance(
            index: index,
            offset: direction.rowOffset,
            animation: RetroMotion.panelRow,
            delay: RetroMotion.panelRowDelay
        ))
    }

    func retroStaggeredEntrance(index: Int, direction: RetroHorizontalMotion) -> some View {
        modifier(RetroStaggeredEntrance(
            index: index,
            offset: direction.rowOffset,
            animation: RetroMotion.panelRow,
            delay: RetroMotion.panelRowDelay
        ))
    }

    func retroHoverEffect() -> some View {
        modifier(RetroHoverEffect())
    }
}
