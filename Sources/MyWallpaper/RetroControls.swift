import SwiftUI

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
                    .accessibilityHidden(true)
            }
            .foregroundStyle(selected ? RetroPalette.paper : RetroPalette.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
            .background(selected ? RetroPalette.ink : Color.clear)
            .overlay { Rectangle().stroke(RetroPalette.ink, lineWidth: selected ? 0 : 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .retroHoverEffect()
        .padding(.leading, selected ? 6 : 0)
        .padding(.bottom, 8)
        .animation(RetroMotion.selection, value: selected)
    }
}

struct RetroChoiceBar<Value: Hashable>: View {
    let values: [Value]
    let selected: Value
    let accessibilityLabel: String
    let title: (Value) -> String
    let accessibilityTitle: (Value) -> String
    let onSelect: (Value) -> Void

    init(
        values: [Value],
        selected: Value,
        accessibilityLabel: String,
        title: @escaping (Value) -> String,
        accessibilityTitle: ((Value) -> String)? = nil,
        onSelect: @escaping (Value) -> Void
    ) {
        self.values = values
        self.selected = selected
        self.accessibilityLabel = accessibilityLabel
        self.title = title
        self.accessibilityTitle = accessibilityTitle ?? title
        self.onSelect = onSelect
    }

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
                .accessibilityValue(value == selected ? "Selected" : "Not selected")
                .accessibilityAddTraits(value == selected ? .isSelected : [])
                .retroHoverEffect()
            }
        }
        .accessibilityRepresentation {
            Picker(
                accessibilityLabel,
                selection: Binding(
                    get: { selected },
                    set: { value in onSelect(value) }
                )
            ) {
                ForEach(values, id: \.self) { value in
                    Text(accessibilityTitle(value)).tag(value)
                }
            }
            .pickerStyle(.radioGroup)
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
            accessibilityLabel: "Appearance",
            title: \.title,
            onSelect: onSelect
        )
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
        .accessibilityRepresentation {
            Toggle(
                title,
                isOn: Binding(
                    get: { isOn },
                    set: { newValue in
                        if newValue != isOn { action() }
                    }
                )
            )
        }
        .retroHoverEffect()
    }
}

struct RetroFact: View {
    let marker: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(marker)
                .font(RetroFont.label(size: 8))
                .accessibilityHidden(true)
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
