import AppKit

/// Opens the macOS control that governs whether USB and Thunderbolt accessories
/// may establish a data connection with the Mac.
@MainActor
enum AccessoryAuthorizationSettings {
    /// The Accessories subsection of Privacy & Security on supported macOS versions.
    static let accessoriesURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AccessorySecurity"
    )!

    /// A safe fallback for macOS versions that do not recognise the subsection deep link.
    static let privacyAndSecurityURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security"
    )!

    @discardableResult
    static func open() -> Bool {
        if NSWorkspace.shared.open(accessoriesURL) {
            return true
        }

        return NSWorkspace.shared.open(privacyAndSecurityURL)
    }
}
