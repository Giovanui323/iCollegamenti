import Foundation

/// Removes locally identifying connection fields from JSON intended for
/// sharing. The persistence format remains untouched; callers sanitize only
/// an explicit export copy.
public enum SharedExportSanitizer {
    private static let sensitiveKeys: Set<String> = [
        "deviceSerialNumber",
        "connectionFingerprint",
        "connectionID",
        "serialNumber",
        "bsdName",
        "mountedVolumeBSDName",
        "mountPath",
        "locationID",
        "id",
        "cableID"
    ]

    public static func redactJSON(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let redacted = redact(object)
        return try? JSONSerialization.data(withJSONObject: redacted, options: [.prettyPrinted, .sortedKeys])
    }

    private static func redact(_ value: Any) -> Any {
        if let array = value as? [Any] {
            return array.map(redact)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                guard !sensitiveKeys.contains(item.key) else { return }
                result[item.key] = redact(item.value)
            }
        }
        if let string = value as? String {
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            let withoutCurrentHome = string.replacingOccurrences(of: homePath, with: "[redacted-home]")
            return withoutCurrentHome.replacingOccurrences(
                of: #"/Users/[^/\s]+"#,
                with: "/Users/[redacted]",
                options: .regularExpression
            )
        }
        return value
    }
}
