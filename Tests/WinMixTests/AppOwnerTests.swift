import XCTest
@testable import WinMix

final class AppOwnerTests: XCTestCase {
    func testBrowserLaunchedByEditorStillBelongsToBrowser() {
        let owner = AppOwner(pid: 20, bundleID: "com.google.chrome.for.testing.helper",
                             enclosingBundleID: "com.google.chrome.for.testing",
                             responsiblePID: 10, responsibleBundleID: "com.microsoft.VSCode")
        XCTAssertEqual(owner.key, "com.google.chrome.for.testing")
        XCTAssertEqual(owner.pid, 20)
    }

    func testNormalHelperKeepsItsAppPID() {
        let owner = AppOwner(pid: 20, bundleID: "com.google.Chrome.helper",
                             enclosingBundleID: "com.google.Chrome",
                             responsiblePID: 10, responsibleBundleID: "com.google.Chrome")
        XCTAssertEqual(owner.key, "com.google.Chrome")
        XCTAssertEqual(owner.pid, 10)
    }

    func testSharedWebKitServiceUsesResponsibleApplication() {
        let owner = AppOwner(pid: 20, bundleID: "com.apple.WebKit.GPU", enclosingBundleID: nil,
                             responsiblePID: 10, responsibleBundleID: "com.microsoft.Outlook")
        XCTAssertEqual(owner.key, "com.microsoft.Outlook")
        XCTAssertEqual(owner.pid, 10)
    }

    func testCommandLineProcessesStaySeparate() {
        let owner = AppOwner(pid: 20, bundleID: "", enclosingBundleID: "com.apple.Terminal",
                             responsiblePID: 10, responsibleBundleID: "com.apple.Terminal")
        XCTAssertEqual(owner.key, "pid:20")
    }
}
