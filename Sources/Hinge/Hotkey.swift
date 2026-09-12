import AppKit
import Carbon.HIToolbox

/// The one system-wide shortcut Hinge registers: recalibrate the flat angle
/// without going near the settings window.
///
/// Carbon's hot key API is the only one that fires while another app is in
/// front and does not ask for Accessibility permission, so it is still the
/// right one to use here.
enum Hotkey {
    private static var ref: EventHotKeyRef?
    private static var action: (() -> Void)?
    private static var handlerInstalled = false

    /// Sets what the shortcut does, and registers the current binding.
    static func bind(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        rebind(keyCode: keyCode, modifiers: modifiers)
    }

    /// Whether the last binding actually took. Another app can already own a
    /// combination, and the failure is silent unless someone looks.
    private(set) static var registered = false

    /// Swaps the binding, keeping whatever the shortcut already does. A binding
    /// with no modifier is refused: it would swallow that key everywhere.
    @discardableResult
    static func rebind(keyCode: Int, modifiers: Int) -> Bool {
        installHandler()
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        guard modifiers != 0 else {
            registered = false
            return false
        }
        let id = EventHotKeyID(signature: OSType(0x484E4745), id: 1) // 'HNGE'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                                         GetApplicationEventTarget(), 0, &self.ref)
        registered = status == noErr
        if !registered { NSLog("Hinge: could not register the shortcut (OSStatus \(status))") }
        return registered
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { Hotkey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    // MARK: - Translating what the user pressed

    /// Carbon wants its own modifier bits, not Cocoa's.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if flags.contains(.command) { carbon |= cmdKey }
        if flags.contains(.option) { carbon |= optionKey }
        if flags.contains(.control) { carbon |= controlKey }
        if flags.contains(.shift) { carbon |= shiftKey }
        return carbon
    }

    /// How a binding reads in the settings window. The key's own name comes
    /// from the event that recorded it, so no keyboard layout table is needed.
    static func label(modifiers: Int, key: String) -> String {
        var text = ""
        if modifiers & controlKey != 0 { text += "⌃" }
        if modifiers & optionKey != 0 { text += "⌥" }
        if modifiers & shiftKey != 0 { text += "⇧" }
        if modifiers & cmdKey != 0 { text += "⌘" }
        return text + key.uppercased()
    }

    /// A shortcut that fires while you are typing elsewhere is a trap, so at
    /// least one of the three non-shift modifiers has to be held.
    static func isUsable(modifiers: Int) -> Bool {
        modifiers & (cmdKey | optionKey | controlKey) != 0
    }

    static func selfCheck() {
        assert(carbonModifiers([.command, .option, .control]) == cmdKey | optionKey | controlKey,
               "Cocoa modifiers must map onto the Carbon bits")
        assert(carbonModifiers([]) == 0, "no modifiers must map to no bits")
        assert(label(modifiers: cmdKey | optionKey | controlKey, key: "h") == "⌃⌥⌘H",
               "a binding must read in the usual modifier order")
        assert(!isUsable(modifiers: 0), "a bare key must be refused")
        assert(!isUsable(modifiers: shiftKey), "shift alone must be refused")
        assert(isUsable(modifiers: controlKey | optionKey | cmdKey), "the default binding must be usable")
        print("Hotkey.selfCheck passed")
    }
}
