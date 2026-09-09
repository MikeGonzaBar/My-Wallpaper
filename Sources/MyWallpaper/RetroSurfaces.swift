import SwiftUI

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
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(RetroPalette.paper.opacity(opacity))
            )
            for y in stride(from: 0, to: Int(size.height), by: 4) {
                for x in stride(from: 0, to: Int(size.width), by: 4)
                where (x / 4 + y / 4).isMultiple(of: 2) {
                    let square = CGRect(x: x, y: y, width: 2, height: 2)
                    context.fill(Path(square), with: .color(RetroPalette.ink.opacity(opacity)))
                }
            }
        }
    }
}
