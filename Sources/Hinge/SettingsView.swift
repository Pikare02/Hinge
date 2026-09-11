import SwiftUI

/// The independent settings window: live angle, the knobs, and the way out.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: AngleState
    var onUseCurrentAngle: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%.0f°", state.angle))
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text("LID ANGLE")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Flat above").font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("\(Int(settings.flatAngle))°")
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.flatAngle, in: 45...135)
                Text("The desktop fills the screen at this angle and above.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button(action: onUseCurrentAngle) {
                    Label("Use this lid angle as full screen", systemImage: "laptopcomputer")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .padding(.top, 6)
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                slider("Perspective", $settings.perspective)
                Text("100% is the viewing distance calibration assumes. Lower softens it.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            slider("Max blur", $settings.blur)
            slider("Shadow", $settings.shadow)

            Divider()

            HStack {
                Text("Closing this window leaves Hinge running.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit Hinge", action: onQuit)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func slider(_ label: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1)
        }
    }
}

/// The current smoothed angle, published for the readout only.
final class AngleState: ObservableObject {
    @Published var angle: Double = 0
}
