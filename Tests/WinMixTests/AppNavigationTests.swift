import XCTest
@testable import WinMix

@MainActor
final class AppNavigationTests: XCTestCase {
    func testRequestSurvivesUntilConsumerAppearsAndIsConsumedOnce() {
        let navigation = AppNavigation()
        XCTAssertFalse(navigation.consumeBrowserSetupRequest())
        navigation.requestBrowserSetup()
        XCTAssertTrue(navigation.browserSetupRequested)
        XCTAssertTrue(navigation.consumeBrowserSetupRequest())
        XCTAssertFalse(navigation.browserSetupRequested)
        XCTAssertFalse(navigation.consumeBrowserSetupRequest())
    }

    func testRepeatedPendingRequestsCoalesceAndLaterRequestWorks() {
        let navigation = AppNavigation()
        navigation.requestBrowserSetup()
        navigation.requestBrowserSetup()
        XCTAssertTrue(navigation.consumeBrowserSetupRequest())
        XCTAssertFalse(navigation.consumeBrowserSetupRequest())
        navigation.requestBrowserSetup()
        XCTAssertTrue(navigation.consumeBrowserSetupRequest())
    }
}
