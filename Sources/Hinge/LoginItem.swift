import ServiceManagement
import SwiftUI

/// Toggles whether macOS opens Hinge at login. The system owns this state, so
/// the toggle reads it back rather than keeping a copy.
struct LoginItemToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Open Hinge at login", isOn: Binding(get: { enabled }, set: setEnabled))
                .font(.system(size: 11, weight: .medium))
            if let problem {
                Text(problem)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
    }

    private func setEnabled(_ wanted: Bool) {
        do {
            if wanted {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        // Trust the system's answer, not what was asked for.
        enabled = SMAppService.mainApp.status == .enabled
    }
}
