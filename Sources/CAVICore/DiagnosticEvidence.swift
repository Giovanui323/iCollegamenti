import Foundation

/// Describes where a diagnostic value came from. A value inferred from a
/// comparison must never be presented as a directly observed hardware fact.
public enum EvidenceSource: String, Codable, Hashable, Sendable {
    case ioRegistryObserved
    case diskArbitrationObserved
    case powerSourceObserved
    case benchmarkMeasured
    case catalogMatched
    case userConfirmed
    case inferred
    case unavailable

    public var isDirectObservation: Bool {
        switch self {
        case .ioRegistryObserved, .diskArbitrationObserved, .powerSourceObserved, .benchmarkMeasured:
            true
        case .catalogMatched, .userConfirmed, .inferred, .unavailable:
            false
        }
    }
}

/// A typed diagnostic value together with its provenance. `nil` is meaningful:
/// it records that macOS did not expose a value without turning absence into a
/// negative diagnosis.
public struct DiagnosticFact<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public let value: Value?
    public let source: EvidenceSource
    public let detail: String?

    public init(value: Value?, source: EvidenceSource, detail: String? = nil) {
        self.value = value
        self.source = source
        self.detail = detail
    }
}

public struct DiagnosticEvidence: Codable, Hashable, Sendable {
    public let label: String
    public let value: String?
    public let source: EvidenceSource

    public init(label: String, value: String? = nil, source: EvidenceSource) {
        self.label = label
        self.value = value
        self.source = source
    }
}

public enum DiagnosticConfidence: String, Codable, Hashable, Sendable {
    case confirmed
    case likely
    case possible
    case insufficientEvidence

    public static func from(evidence: [DiagnosticEvidence]) -> Self {
        let usable = evidence.filter { $0.source != .unavailable }
        guard !usable.isEmpty else { return .insufficientEvidence }

        if usable.contains(where: { $0.source.isDirectObservation || $0.source == .userConfirmed }) {
            return .confirmed
        }
        if usable.contains(where: { $0.source == .catalogMatched }) {
            return .likely
        }
        return .possible
    }
}

public enum WarningLevel: String, Codable, Hashable, Sendable {
    case info
    case attention
    case critical
}
