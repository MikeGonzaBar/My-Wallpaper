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
        .custom("Helvetica Neue", fixedSize: size).weight(.bold)
    }

    static func body(size: CGFloat = 12) -> Font {
        .custom("Menlo", fixedSize: size)
    }

    static func label(size: CGFloat = 11) -> Font {
        .custom("Menlo", fixedSize: size).weight(.bold)
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

struct RetroNavigationItem: View {
    let marker: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(marker)
                    .font(RetroFont.label(size: 9))
                    .frame(width: 24)
                Text(title)
                    .font(RetroFont.label(size: 11))
                Spacer()
                Text(selected ? "◀" : "")
                    .font(RetroFont.label(size: 9))
            }
            .foregroundStyle(selected ? RetroPalette.paper : RetroPalette.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
            .background(selected ? RetroPalette.ink : Color.clear)
            .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: selected ? 0 : 1) }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .retroHoverEffect()
        .padding(.leading, selected ? 6 : 0)
        .padding(.bottom, 8)
        .animation(RetroMotion.selection, value: selected)
    }
}

struct RetroPageHeader<Trailing: View>: View {
    let code: String
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(code: String, title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.code = code
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(code)
                    .font(RetroFont.label(size: 9))
                    .foregroundStyle(RetroPalette.secondaryInk)
                Text(title)
                    .font(RetroFont.headline(size: 30))
                    .tracking(-0.8)
                Text(subtitle)
                    .font(RetroFont.body(size: 10))
                    .foregroundStyle(RetroPalette.secondaryInk)
            }
            Spacer()
            trailing
        }
        .padding(.bottom, 4)
    }
}

struct RetroStatusBadge: View {
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(active ? RetroPalette.ink : RetroPalette.paper)
                .frame(width: 8, height: 8)
                .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
            Text(text.uppercased())
                .lineLimit(1)
        }
        .font(RetroFont.label(size: 9))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RetroPalette.paper)
        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
    }
}

struct RetroWindow<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: title)
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RetroPalette.paper)
        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
        .background {
            Rectangle()
                .fill(RetroPalette.ink)
                .offset(x: 3, y: 3)
        }
        .padding(.trailing, 3)
        .padding(.bottom, 3)
    }
}

struct RetroTitleBar: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            TitleBarLines()
            Text(title)
                .font(RetroFont.label(size: 10))
                .padding(.horizontal, 6)
                .lineLimit(1)
            TitleBarLines()
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(RetroPalette.paper)
        .overlay(alignment: .bottom) {
            Rectangle().fill(RetroPalette.ink).frame(height: 1)
        }
    }
}

struct TitleBarLines: View {
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { _ in
                Rectangle().fill(RetroPalette.ink).frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct RetroDivider: View {
    var body: some View {
        VStack(spacing: 2) {
            Rectangle().fill(RetroPalette.ink).frame(height: 1)
            Rectangle().fill(RetroPalette.ink).frame(height: 1)
        }
    }
}

struct DitherPattern: View {
    var opacity = 1.0

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(RetroPalette.paper.opacity(opacity)))
            for y in stride(from: 0, to: Int(size.height), by: 4) {
                for x in stride(from: 0, to: Int(size.width), by: 4) where (x / 4 + y / 4).isMultiple(of: 2) {
                    let square = CGRect(x: x, y: y, width: 2, height: 2)
                    context.fill(Path(square), with: .color(RetroPalette.ink.opacity(opacity)))
                }
            }
        }
    }
}

struct RetroChoiceBar<Value: Hashable>: View {
    let values: [Value]
    let selected: Value
    let title: (Value) -> String
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Text(title(value))
                        .font(RetroFont.label(size: 9))
                        .foregroundStyle(value == selected ? RetroPalette.paper : RetroPalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(Rectangle())
                        .background(value == selected ? RetroPalette.ink : RetroPalette.paper)
                        .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
                .retroHoverEffect()
            }
        }
    }
}

struct AppearanceModePicker: View {
    let mode: AppearanceMode
    let onSelect: (AppearanceMode) -> Void

    var body: some View {
        RetroChoiceBar(
            values: AppearanceMode.allCases,
            selected: mode,
            title: \.title,
            onSelect: onSelect
        )
        .accessibilityLabel("Appearance")
    }
}

struct DiagonalAppearanceTransition: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let trigger: UUID

    @State private var progress = 0.0
    @State private var isVisible = false
    @State private var animationToken = UUID()

    var body: some View {
        GeometryReader { proxy in
            if isVisible {
                Canvas { context, size in
                    let diagonal = hypot(size.width, size.height)
                    context.translateBy(x: size.width / 2, y: size.height / 2)
                    context.rotate(by: .degrees(45))
                    let leadingEdge = -diagonal * 2 + progress * diagonal * 4
                    context.fill(
                        Path(CGRect(x: leadingEdge, y: -diagonal * 2, width: diagonal * 2, height: diagonal * 4)),
                        with: .color(RetroPalette.desktop)
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            playTransition()
        }
    }

    private func playTransition() {
        guard !reduceMotion else { return }
        let token = UUID()
        animationToken = token
        progress = 0
        isVisible = true
        withAnimation(.easeInOut(duration: 0.48)) {
            progress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard animationToken == token else { return }
            isVisible = false
        }
    }
}

struct RetroCheckbox: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Rectangle().fill(RetroPalette.paper)
                    if isOn {
                        Rectangle().fill(RetroPalette.ink).padding(3)
                    }
                }
                .frame(width: 14, height: 14)
                .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
                Text(title).font(RetroFont.label(size: 10))
                Spacer()
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .retroHoverEffect()
    }
}

struct RetroFact: View {
    let marker: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(marker).font(RetroFont.label(size: 8))
            Text(text).font(RetroFont.body(size: 10))
        }
    }
}

struct RetroButtonStyle: ButtonStyle {
    var primary = false
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RetroFont.label(size: compact ? 9 : 10))
            .foregroundStyle(primary ? RetroPalette.paper : RetroPalette.ink)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(minHeight: compact ? 26 : 32)
            .contentShape(Rectangle())
            .background(primary ? RetroPalette.ink : RetroPalette.paper)
            .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: 1) }
            .background {
                Rectangle()
                    .fill(RetroPalette.ink)
                    .offset(x: configuration.isPressed ? 0 : 2, y: configuration.isPressed ? 0 : 2)
            }
            .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
            .padding(.trailing, 2)
            .padding(.bottom, 2)
            .retroHoverEffect()
    }
}
