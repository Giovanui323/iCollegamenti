import Foundation

/// Creates display-safe identifiers for cables registered by the user.
/// The code identifies an app catalog entry; it does not claim that macOS can
/// read a physical identifier from every cable.
public enum CableIdentityPolicy {
    public static func code(for id: UUID) -> String {
        let compactIdentifier = id.uuidString.replacingOccurrences(of: "-", with: "")
        return "CAV-\(compactIdentifier.prefix(6).uppercased())"
    }

    public static func isValid(_ code: String) -> Bool {
        code.range(of: "^CAV-[0-9A-F]{6}$", options: .regularExpression) != nil
    }
}
