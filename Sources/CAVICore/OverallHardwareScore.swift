import Foundation

public struct HardwareScoreComponents: Codable, Hashable, Sendable {
    public let cable: Int?
    public let connection: Int?
    public let performance: Int?
    public let health: Int?
    public let power: Int?
    public let stability: Int?

    public init(cable: Int? = nil, connection: Int?, performance: Int?, health: Int?, power: Int?, stability: Int?) {
        self.cable = cable
        self.connection = connection
        self.performance = performance
        self.health = health
        self.power = power
        self.stability = stability
    }
}


public enum OverallHardwareScoreLevel: String, Codable, Hashable, Sendable {
    case excellent
    case good
    case attention
    case critical
}

public struct OverallHardwareScoreResult: Codable, Hashable, Sendable {
    public let value: Int
    public let level: OverallHardwareScoreLevel
    public let includedComponentCount: Int

    public init(value: Int, level: OverallHardwareScoreLevel, includedComponentCount: Int) {
        self.value = value
        self.level = level
        self.includedComponentCount = includedComponentCount
    }
}

/// Combines only components for which the app has an observed value. An absent
/// hardware capability is never silently converted into a perfect score.
public enum OverallHardwareScore {
    public static func calculate(_ components: HardwareScoreComponents) -> OverallHardwareScoreResult? {
        let values = [components.cable, components.connection, components.performance, components.health, components.power, components.stability]
            .compactMap { $0 }
            .map { min(100, max(0, $0)) }
        guard !values.isEmpty else { return nil }
        let value = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        let level: OverallHardwareScoreLevel
        switch value {
        case 90...: level = .excellent
        case 70...: level = .good
        case 40...: level = .attention
        default: level = .critical
        }
        return OverallHardwareScoreResult(value: value, level: level, includedComponentCount: values.count)
    }
}
