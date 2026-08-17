import Foundation

public struct PortRecommendation: Codable, Hashable, Sendable {
    public let deviceName: String
    public let suggestion: String
    public let reason: String
    
    public init(deviceName: String, suggestion: String, reason: String) {
        self.deviceName = deviceName
        self.suggestion = suggestion
        self.reason = reason
    }
}
