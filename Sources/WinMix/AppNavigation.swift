import Combine

@MainActor
final class AppNavigation: ObservableObject {
    @Published private(set) var browserSetupRequested = false

    func requestBrowserSetup() { browserSetupRequested = true }

    @discardableResult
    func consumeBrowserSetupRequest() -> Bool {
        guard browserSetupRequested else { return false }
        browserSetupRequested = false
        return true
    }
}
