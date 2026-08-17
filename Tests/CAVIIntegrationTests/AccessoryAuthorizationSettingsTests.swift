import XCTest
@testable import CAVI

@MainActor
final class AccessoryAuthorizationSettingsTests: XCTestCase {
    func testAccessoryAuthorizationTargetsPrivacyAndSecurityAccessories() {
        let destination = AccessoryAuthorizationSettings.accessoriesURL

        XCTAssertEqual(
            destination.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AccessorySecurity"
        )
    }

    func testFallbackTargetsPrivacyAndSecurity() {
        let fallback = AccessoryAuthorizationSettings.privacyAndSecurityURL

        XCTAssertEqual(
            fallback.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security"
        )
    }
}
