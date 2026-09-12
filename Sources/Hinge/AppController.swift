import AppKit
import CoreGraphics
import SwiftUI

/// Wires the sensor, the capture stream, the overlay and the settings window.
final class AppController: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let angleState = AngleState()
    private let capture = ScreenCapture()
    // Created on the main thread, which is where the delegate callbacks run.
    private lazy var updater = MainActor.assumeIsolated { Updater() }
    private var sensor: LidAngleSensor?

    private var overlayWindow: NSWindow!
    private var settingsWindow: NSWindow!
    private var statusItem: NSStatusItem!
    private var tiltView: TiltView!

    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval?
    private var confirmation: DispatchWorkItem?
    private var updateTimer: Timer?
    private var smoothedAngle: Double?

    /// The overlay is only raised once the desktop actually tilts. While flat it
    /// would be an exact copy of the screen, so hiding it changes nothing to
    /// look at and leaves the menu bar and Dock usable.
    private var overlayVisible = false
    private let showAboveTilt = 1.0
    private let hideBelowTilt = 0.2

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two copies would each capture the other's overlay, and the screen
        // would fill with nested copies of itself.
        if let running = alreadyRunning() {
            running.activate()
            NSApp.terminate(nil)
            return
        }

        guard let sensor = LidAngleSensor() else {
            fail("No lid angle sensor found. Hinge needs an Apple silicon MacBook with a lid angle sensor.")
            return
        }
        self.sensor = sensor

        guard CGPreflightScreenCaptureAccess() else {
            requestScreenRecording()
            return
        }

        buildOverlayWindow()
        buildSettingsWindow()
        buildStatusItem()
        buildMainMenu()

        startSensorLoop()

        settings.bindHotkey { [weak self] in self?.useCurrentAngle() }

        capture.onFrame = { [weak self] surface in
            DispatchQueue.main.async { self?.tiltView.show(surface) }
        }
        Task { @MainActor in
            do { try await capture.start() }
            catch { fail("Could not start screen capture: \(error.localizedDescription)") }
        }

        startUpdateChecks()

        showSettings()
    }

    /// Looks for a release now and every six hours after. Only the automatic
    /// setting lets a find install itself; otherwise it waits in settings.
    private func startUpdateChecks() {
        let check = { [weak self] in
            guard let self else { return }
            Task { await self.updater.check(install: self.settings.autoUpdate) }
        }
        check()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in check() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon brings the settings window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSettings()
        return true
    }

    /// Another instance of this app, if one is already up.
    private func alreadyRunning() -> NSRunningApplication? {
        let identifier = Bundle.main.bundleIdentifier ?? "local.hinge"
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    // MARK: - Windows

    private func buildOverlayWindow() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        overlayWindow = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        overlayWindow.level = .screenSaver
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlayWindow.backgroundColor = .black
        overlayWindow.isOpaque = true
        // The overlay is a picture, not a surface to click; never trap input.
        overlayWindow.ignoresMouseEvents = true

        tiltView = TiltView(frame: NSRect(origin: .zero, size: screen.frame.size))
        tiltView.autoresizingMask = [.width, .height]
        overlayWindow.contentView = tiltView
    }

    private func buildSettingsWindow() {
        let view = SettingsView(settings: settings, state: angleState, updater: updater,
                                onUseCurrentAngle: { [weak self] in self?.useCurrentAngle() },
                                onQuit: { NSApp.terminate(nil) })
        let hosting = NSHostingView(rootView: view)
        settingsWindow = NSWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
        settingsWindow.title = "Hinge"
        settingsWindow.contentView = hosting
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        settingsWindow.setContentSize(hosting.fittingSize)
        settingsWindow.center()
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "laptopcomputer",
                                          accessibilityDescription: "Hinge")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(showSettings)
    }

    private func buildMainMenu() {
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Hinge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func showSettings() {
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Sensor

    /// The lid is read once per displayed frame, locked to the display. A timer
    /// of its own would drift against the refresh and land halfway through a
    /// frame, which costs up to another frame before the panel shows the angle.
    /// The read itself is under a millisecond, so it can sit on the main thread
    /// where the drawing already is.
    private func startSensorLoop() {
        let screen = overlayWindow.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let link = screen.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {
        guard let raw = sensor?.read() else { return }
        let now = CACurrentMediaTime()
        let dt = lastTick.map { now - $0 } ?? 0
        lastTick = now
        let smoothed = Tilt.smooth(previous: smoothedAngle ?? raw, target: raw, dt: dt)
        smoothedAngle = smoothed
        render(angle: smoothed)
    }

    private func render(angle: Double) {
        if settingsWindow.isVisible { angleState.angle = angle }
        let tilt = Tilt.tiltDegrees(lidAngle: angle, flatAngle: settings.flatAngle)
        setOverlay(visible: tilt > (overlayVisible ? hideBelowTilt : showAboveTilt))
        guard overlayVisible else { return }
        tiltView.apply(tiltDegrees: tilt, settings: settings)
    }

    private func setOverlay(visible: Bool) {
        guard visible != overlayVisible else { return }
        overlayVisible = visible
        // The settings window only outranks the overlay while the overlay is up;
        // the rest of the time it behaves like any ordinary window.
        settingsWindow.level = visible ? .init(rawValue: NSWindow.Level.screenSaver.rawValue + 1) : .normal
        // orderFrontRegardless keeps focus where it is.
        if visible { overlayWindow.orderFrontRegardless() } else { overlayWindow.orderOut(nil) }
    }

    /// Treat the current lid position as the flat, full-screen angle.
    private func useCurrentAngle() {
        settings.flatAngle = smoothedAngle ?? settings.flatAngle
        confirmCalibration()
    }

    /// The shortcut works with every window hidden, so the new angle is shown
    /// in the menu bar for a moment; otherwise nothing on screen would change.
    private func confirmCalibration() {
        guard let button = statusItem?.button else { return }
        button.title = String(format: " %.0f°", settings.flatAngle)
        confirmation?.cancel()
        let work = DispatchWorkItem { button.title = "" }
        confirmation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: - Failure

    /// Triggers the system prompt and points the user at the right settings pane.
    private func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Hinge needs Screen Recording permission"
        alert.informativeText = "Turn Hinge on under Privacy & Security › Screen Recording, then open Hinge again."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn,
           let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(pane)
        }
        NSApp.terminate(nil)
    }

    private func fail(_ message: String) {
        overlayWindow?.orderOut(nil)
        let alert = NSAlert()
        alert.messageText = "Hinge can't run"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
}
