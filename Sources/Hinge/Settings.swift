import Foundation
import Combine
import Carbon.HIToolbox

/// User-facing knobs, persisted between launches.
final class Settings: ObservableObject {
    @Published var perspective: Double { didSet { save(perspective, "perspective") } }
    @Published var blur: Double { didSet { save(blur, "blur") } }
    @Published var shadow: Double { didSet { save(shadow, "shadow") } }
    /// At and above this lid angle the desktop sits flat and fills the screen.
    /// Sensors differ per machine, so the user can recalibrate it.
    @Published var flatAngle: Double { didSet { save(flatAngle, "flatAngle") } }

    /// The system-wide shortcut that calibrates the flat angle where you sit.
    /// The key's own name is kept alongside the code so the binding can be
    /// shown back without consulting the keyboard layout.
    @Published var hotkeyKeyCode: Int { didSet { save(hotkeyKeyCode, "hotkeyKeyCode"); rebind() } }
    @Published var hotkeyModifiers: Int { didSet { save(hotkeyModifiers, "hotkeyModifiers"); rebind() } }
    @Published var hotkeyKey: String { didSet { save(hotkeyKey, "hotkeyKey") } }

    var hotkeyLabel: String { Hotkey.label(modifiers: hotkeyModifiers, key: hotkeyKey) }

    /// Whether a newer release installs itself as soon as it is found.
    @Published var autoUpdate: Bool { didSet { save(autoUpdate, "autoUpdate") } }

    /// False once a binding is refused, which is what another app already
    /// owning that combination looks like.
    @Published private(set) var hotkeyWorks = true

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "perspective": 1.0, "blur": 0.65, "shadow": 0.6, "flatAngle": 90.0,
            // ⌃⌥⌘H: three modifiers no single app claims, on Hinge's own initial.
            "hotkeyKeyCode": kVK_ANSI_H,
            "hotkeyModifiers": controlKey | optionKey | cmdKey,
            "hotkeyKey": "H",
            "autoUpdate": false,
        ])
        perspective = defaults.double(forKey: "perspective")
        blur = defaults.double(forKey: "blur")
        shadow = defaults.double(forKey: "shadow")
        flatAngle = defaults.double(forKey: "flatAngle")
        hotkeyKeyCode = defaults.integer(forKey: "hotkeyKeyCode")
        hotkeyModifiers = defaults.integer(forKey: "hotkeyModifiers")
        hotkeyKey = defaults.string(forKey: "hotkeyKey") ?? "H"
        autoUpdate = defaults.bool(forKey: "autoUpdate")
    }

    /// Wires the shortcut up for the first time; later changes rebind on their own.
    func bindHotkey(action: @escaping () -> Void) {
        Hotkey.bind(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers, action: action)
        hotkeyWorks = Hotkey.registered
    }

    private func rebind() {
        hotkeyWorks = Hotkey.rebind(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
