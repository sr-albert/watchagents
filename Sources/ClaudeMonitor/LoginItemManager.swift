import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail (e.g. running an unbundled `swift run` binary
            // outside /Applications); fall through and re-read the real status
            // below so the toggle reflects what actually happened.
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
