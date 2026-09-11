import Foundation
import Combine

/// User-facing knobs, persisted between launches.
final class Settings: ObservableObject {
    @Published var perspective: Double { didSet { save(perspective, "perspective") } }
    @Published var blur: Double { didSet { save(blur, "blur") } }
    @Published var shadow: Double { didSet { save(shadow, "shadow") } }
    /// At and above this lid angle the desktop sits flat and fills the screen.
    /// Sensors differ per machine, so the user can recalibrate it.
    @Published var flatAngle: Double { didSet { save(flatAngle, "flatAngle") } }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["perspective": 1.0, "blur": 0.65, "shadow": 0.6, "flatAngle": 90.0])
        perspective = defaults.double(forKey: "perspective")
        blur = defaults.double(forKey: "blur")
        shadow = defaults.double(forKey: "shadow")
        flatAngle = defaults.double(forKey: "flatAngle")
    }

    private func save(_ value: Double, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
