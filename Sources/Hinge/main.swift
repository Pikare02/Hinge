import AppKit

// --selfcheck and --probe let the moving parts be verified from a terminal,
// without granting permissions or taking over the screen.
switch CommandLine.arguments.dropFirst().first {
case "--selfcheck":
    Tilt.selfCheck()
    Hotkey.selfCheck()
    MainActor.assumeIsolated { Updater.selfCheck() }

case "--probe":
    guard let sensor = LidAngleSensor(), let angle = sensor.read() else {
        print("no lid angle sensor")
        exit(1)
    }
    print("lid angle: \(angle)°")
    print("tilt at flat angle 90°: \(Tilt.tiltDegrees(lidAngle: angle, flatAngle: 90))°")
    print("screen recording permission: \(CGPreflightScreenCaptureAccess())")

case "--hotkey":
    // Registration fails silently when another app already owns the
    // combination, so this reports whether the binding actually took.
    _ = NSApplication.shared
    let settings = Settings()
    print("shortcut: \(settings.hotkeyLabel)")
    print("registered: \(Hotkey.rebind(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers))")

default:
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.regular)
    app.run()
}
