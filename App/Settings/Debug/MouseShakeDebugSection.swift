#if DEBUG
import AiboCore
import SwiftUI

struct MouseShakeDebugSection: View {
    @State private var settings = MouseShakeDebugSettings.shared

    var body: some View {
        Section {
            intField("Stroke Distance", unit: "pt", value: strokeDistanceBinding)
            intField("Window", unit: "ms", value: windowBinding)
            intField("Reversals", unit: "", value: reversalsBinding)
            intField("Travel", unit: "pt", value: travelBinding)
            intField("Cooldown", unit: "ms", value: cooldownBinding)
            intField("Proximity Pad", unit: "pt", value: paddingBinding)
            doubleField("Distance", unit: "×", value: factorBinding)
            intField("Duration", unit: "ms", value: durationBinding)

            HStack {
                Button {
                    AiboPanelController.shared.debugTriggerDodge()
                } label: {
                    Text(verbatim: "Test Dodge")
                }
                Button {
                    settings.reset()
                } label: {
                    Text(verbatim: "Reset")
                }
            }

            Text(verbatim: "Shake the pointer left and right over Aibo. It hops toward the opposite 50/50 quadrant, along the line through the screen center, and stays there. Release builds use the Reset values.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(verbatim: "Mouse Shake Dodge")
        }
    }

    private func intField(_ title: String, unit: String, value: Binding<Int>) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField(
                    value: value,
                    format: .number
                ) {
                    Text(verbatim: title)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                if !unit.isEmpty {
                    Text(verbatim: unit)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                }
            }
        } label: {
            Text(verbatim: title)
        }
    }

    private func doubleField(_ title: String, unit: String, value: Binding<Double>) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                TextField(
                    value: value,
                    format: .number.precision(.fractionLength(1))
                ) {
                    Text(verbatim: title)
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                Text(verbatim: unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .leading)
            }
        } label: {
            Text(verbatim: title)
        }
    }

    private var strokeDistanceBinding: Binding<Int> {
        Binding(
            get: { Int(settings.config.strokeMinDistance.rounded()) },
            set: { settings.config.strokeMinDistance = Double(max($0, 1)) }
        )
    }

    private var windowBinding: Binding<Int> {
        Binding(
            get: { Int((settings.config.window * 1000).rounded()) },
            set: { settings.config.window = Double(max($0, 50)) / 1000 }
        )
    }

    private var reversalsBinding: Binding<Int> {
        Binding(
            get: { settings.config.minReversals },
            set: { settings.config.minReversals = max($0, 1) }
        )
    }

    private var travelBinding: Binding<Int> {
        Binding(
            get: { Int(settings.config.minTravel.rounded()) },
            set: { settings.config.minTravel = Double(max($0, 1)) }
        )
    }

    private var cooldownBinding: Binding<Int> {
        Binding(
            get: { Int((settings.config.cooldown * 1000).rounded()) },
            set: { settings.config.cooldown = Double(max($0, 0)) / 1000 }
        )
    }

    private var paddingBinding: Binding<Int> {
        Binding(
            get: { Int(settings.config.proximityPadding.rounded()) },
            set: { settings.config.proximityPadding = Double(max($0, 0)) }
        )
    }

    private var factorBinding: Binding<Double> {
        Binding(
            get: { settings.config.dodgeDistanceFactor },
            set: { settings.config.dodgeDistanceFactor = max($0, 0.1) }
        )
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { Int((settings.config.dodgeDuration * 1000).rounded()) },
            set: { settings.config.dodgeDuration = Double(max($0, 0)) / 1000 }
        )
    }
}
#endif
