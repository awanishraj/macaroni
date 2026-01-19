import SwiftUI

/// A reusable toggle row component with icon and optional description
struct ToggleRow: View {
    let label: String
    let description: String?
    let icon: String?
    let iconColor: Color
    @Binding var isOn: Bool

    init(
        label: String,
        description: String? = nil,
        icon: String? = nil,
        iconColor: Color = .secondary,
        isOn: Binding<Bool>
    ) {
        self.label = label
        self.description = description
        self.icon = icon
        self.iconColor = iconColor
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .foregroundColor(isOn ? iconColor : .secondary)
                        .frame(width: 16)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.caption)

                    if let description = description {
                        Text(description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// A section header with optional trailing accessory
struct SectionHeader: View {
    let title: String
    let icon: String
    let trailing: AnyView?

    init(title: String, icon: String, trailing: AnyView? = nil) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Spacer()
            trailing
        }
    }
}

/// A status indicator badge
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}

/// A labeled value display
struct LabeledValue: View {
    let label: String
    let value: String
    let valueColor: Color

    init(label: String, value: String, valueColor: Color = .primary) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
    }
}

/// A picker row with label
struct PickerRow<T: Hashable, Content: View>: View {
    let label: String
    @Binding var selection: T
    let content: () -> Content

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Picker("", selection: $selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

/// An action row with button
struct ActionRow: View {
    let label: String
    let icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon = icon {
                    Image(systemName: icon)
                }
                Text(label)
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
    }
}

#Preview {
    VStack(spacing: 16) {
        SectionHeader(title: "Display", icon: "display")

        ToggleRow(
            label: "Auto Brightness",
            description: "Adjust based on sunrise/sunset",
            icon: "sunrise",
            iconColor: .orange,
            isOn: .constant(true)
        )

        StatusBadge(text: "Active", color: .green)

        LabeledValue(label: "Current", value: "75%")

        ActionRow(label: "Open Settings", icon: "gear") {
            // Preview action
        }
    }
    .padding()
    .frame(width: 280)
}
