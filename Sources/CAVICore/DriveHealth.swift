import Foundation

public enum SMARTStatus: String, Codable, Hashable, Sendable {
    case verified
    case failing
    case unavailable
}

public enum DriveHealthWarning: String, Codable, Hashable, Sendable {
    case smartFailure
    case highTemperature
    case lowRemainingLife
    case mediaErrors
}

public enum DriveHealthLevel: String, Codable, Hashable, Sendable {
    case excellent
    case good
    case warning
    case critical
}

public struct DriveHealthInput: Codable, Hashable, Sendable {
    public let smartStatus: SMARTStatus
    public let temperatureCelsius: Double?
    public let remainingLifePercent: Int?
    public let mediaErrorCount: Int?

    public init(
        smartStatus: SMARTStatus = .unavailable,
        temperatureCelsius: Double? = nil,
        remainingLifePercent: Int? = nil,
        mediaErrorCount: Int? = nil
    ) {
        self.smartStatus = smartStatus
        self.temperatureCelsius = temperatureCelsius
        self.remainingLifePercent = remainingLifePercent
        self.mediaErrorCount = mediaErrorCount
    }
}

public struct DriveHealthAssessment: Codable, Hashable, Sendable {
    public let score: Int
    public let level: DriveHealthLevel
    public let warnings: [DriveHealthWarning]

    public init(score: Int, level: DriveHealthLevel, warnings: [DriveHealthWarning]) {
        self.score = score
        self.level = level
        self.warnings = warnings
    }
}

/// Scores only observed health signals. Missing SMART or temperature data are
/// neutral rather than being guessed or treated as a fault.
public enum DriveHealthScorer {
    public static func assess(_ input: DriveHealthInput) -> DriveHealthAssessment {
        var score = 100
        var warnings: [DriveHealthWarning] = []

        if input.smartStatus == .failing {
            score -= 50
            warnings.append(.smartFailure)
        }
        if let temperature = input.temperatureCelsius, temperature >= 70 {
            score -= 20
            warnings.append(.highTemperature)
        }
        if let remainingLife = input.remainingLifePercent, remainingLife <= 10 {
            score -= 25
            warnings.append(.lowRemainingLife)
        }
        if let errors = input.mediaErrorCount, errors > 0 {
            score -= min(20, errors * 2)
            warnings.append(.mediaErrors)
        }
        score = max(0, score)
        let level: DriveHealthLevel
        switch score {
        case 90...: level = .excellent
        case 70...: level = .good
        case 40...: level = .warning
        default: level = .critical
        }
        return DriveHealthAssessment(score: score, level: level, warnings: warnings)
    }
}
