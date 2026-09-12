import SwiftUI

/// The independent settings window: live angle, the knobs, and the way out.
struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: AngleState
    @ObservedObject var updater: Updater
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

                HotkeyRecorder(settings: settings)
                Text("The shortcut does the same thing from any app, so you can calibrate while sitting the way you normally sit.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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

            LoginItemToggle()
            UpdateSection(settings: settings, updater: updater)

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

/// Shows the current shortcut and records a new one. While recording, the next
/// key press is taken as the binding rather than reaching the rest of the app.
struct HotkeyRecorder: View {
    @ObservedObject var settings: Settings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Shortcut").font(.system(size: 11, weight: .medium))
                Spacer()
                Button(recording ? "Press keys…" : settings.hotkeyLabel) {
                    recording ? stop() : start()
                }
                .font(.system(size: 11).monospaced())
            }
            if !settings.hotkeyWorks {
                Text("Another app already owns this combination. Pick a different one.")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 6)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func record(_ event: NSEvent) {
        // Escape backs out and leaves the old binding alone.
        guard event.keyCode != 53 else { return stop() }
        let modifiers = Hotkey.carbonModifiers(event.modifierFlags)
        // A binding without a real modifier would swallow that key everywhere,
        // so keep listening until the user holds one.
        guard Hotkey.isUsable(modifiers: modifiers) else { return }
        settings.hotkeyKeyCode = Int(event.keyCode)
        settings.hotkeyModifiers = modifiers
        settings.hotkeyKey = event.charactersIgnoringModifiers?.uppercased() ?? "?"
        stop()
    }
}

/// The version in the bundle, what GitHub has, and the one button between them.
struct UpdateSection: View {
    @ObservedObject var settings: Settings
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Install updates automatically", isOn: $settings.autoUpdate)
                .font(.system(size: 11, weight: .medium))
            HStack {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(failed ? .red : .secondary)
                Spacer()
                button
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var button: some View {
        switch updater.state {
        case .available(let version):
            Button("Update to \(version)") { Task { await updater.install() } }
        case .checking, .installing:
            ProgressView().controlSize(.small)
        default:
            Button("Check for updates") { Task { await updater.check(install: false) } }
        }
    }

    private var failed: Bool {
        if case .failed = updater.state { return true }
        return false
    }

    private var status: String {
        switch updater.state {
        case .idle: return "Version \(Updater.currentVersion)."
        case .checking: return "Checking…"
        case .upToDate: return "Version \(Updater.currentVersion) is the latest."
        case .available(let version): return "Version \(version) is available."
        case .installing: return "Downloading and replacing Hinge…"
        case .failed(let message): return message
        }
    }
}
