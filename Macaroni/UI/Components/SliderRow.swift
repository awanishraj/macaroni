import SwiftUI

/// A reusable slider row component with label, value display, and icons
struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let leadingIcon: String?
    let trailingIcon: String?
    let unit: String
    let showValue: Bool

    init(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        step: Double = 0.01,
        leadingIcon: String? = nil,
        trailingIcon: String? = nil,
        unit: String = "%",
        showValue: Bool = true
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.step = step
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
        self.unit = unit
        self.showValue = showValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if showValue {
                    Text(formattedValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                if let icon = leadingIcon {
                    Image(systemName: icon)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .frame(width: 16)
                }

                Slider(value: $value, in: range, step: step)

                if let icon = trailingIcon {
                    Image(systemName: icon)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .frame(width: 16)
                }
            }
        }
    }

    private var formattedValue: String {
        if unit == "%" {
            return "\(Int(value * 100))%"
        } else if unit == "°C" || unit == "°" {
            return "\(Int(value))°C"
        } else {
            return String(format: "%.1f%@", value, unit)
        }
    }
}

/// A percentage-based slider row
struct PercentSliderRow: View {
    let label: String
    @Binding var value: Double
    let leadingIcon: String?
    let trailingIcon: String?

    init(
        label: String,
        value: Binding<Double>,
        leadingIcon: String? = nil,
        trailingIcon: String? = nil
    ) {
        self.label = label
        self._value = value
        self.leadingIcon = leadingIcon
        self.trailingIcon = trailingIcon
    }

    var body: some View {
        SliderRow(
            label: label,
            value: $value,
            range: 0...1,
            step: 0.01,
            leadingIcon: leadingIcon,
            trailingIcon: trailingIcon,
            unit: "%"
        )
    }
}

/// A temperature-based slider row
struct TemperatureSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(value))°C")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Text("\(Int(range.lowerBound))°")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Slider(value: $value, in: range, step: 1)

                Text("\(Int(range.upperBound))°")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SliderRow(
            label: "Brightness",
            value: .constant(0.75),
            leadingIcon: "sun.min",
            trailingIcon: "sun.max"
        )

        PercentSliderRow(
            label: "Volume",
            value: .constant(0.5),
            leadingIcon: "speaker.fill",
            trailingIcon: "speaker.wave.3.fill"
        )

        TemperatureSliderRow(
            label: "Trigger Temperature",
            value: .constant(70),
            range: 50...90
        )
    }
    .padding()
    .frame(width: 280)
}
