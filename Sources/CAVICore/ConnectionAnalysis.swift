import Foundation

public struct BandwidthConsumer: Codable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let requestedSpeedBps: UInt64?

    public init(id: String, label: String, requestedSpeedBps: UInt64?) {
        self.id = id
        self.label = label
        self.requestedSpeedBps = requestedSpeedBps
    }
}

public struct BandwidthBudget: Codable, Hashable, Sendable {
    public let uplinkSpeedBps: UInt64?
    public let potentialDemandBps: UInt64?
    public let saturationPercent: Int?
    public let consumers: [BandwidthConsumer]
    public let hasIncompleteDemand: Bool

    public init(
        uplinkSpeedBps: UInt64?,
        potentialDemandBps: UInt64?,
        saturationPercent: Int?,
        consumers: [BandwidthConsumer],
        hasIncompleteDemand: Bool
    ) {
        self.uplinkSpeedBps = uplinkSpeedBps
        self.potentialDemandBps = potentialDemandBps
        self.saturationPercent = saturationPercent
        self.consumers = consumers
        self.hasIncompleteDemand = hasIncompleteDemand
    }
}

public enum BandwidthBudgetCalculator {
    public static func calculate(
        uplinkSpeedBps: UInt64?,
        consumers: [BandwidthConsumer]
    ) -> BandwidthBudget {
        let knownConsumers = consumers.filter { $0.requestedSpeedBps != nil }
        let potentialDemandBps = knownConsumers.reduce(UInt64(0)) { partial, consumer in
            partial + (consumer.requestedSpeedBps ?? 0)
        }
        let hasDemand = !knownConsumers.isEmpty
        let saturationPercent: Int?
        if let uplinkSpeedBps, uplinkSpeedBps > 0, hasDemand {
            saturationPercent = Int((Double(potentialDemandBps) / Double(uplinkSpeedBps) * 100).rounded())
        } else {
            saturationPercent = nil
        }

        return BandwidthBudget(
            uplinkSpeedBps: uplinkSpeedBps,
            potentialDemandBps: hasDemand ? potentialDemandBps : nil,
            saturationPercent: saturationPercent,
            consumers: consumers,
            hasIncompleteDemand: knownConsumers.count != consumers.count
        )
    }
}

public enum ConnectionConstraintKind: String, Codable, Hashable, Sendable {
    case hub
    case controller
    case port
    case device
    case unknown
}

public struct ConnectionConstraint: Codable, Hashable, Sendable {
    public let label: String
    public let maximumSpeedBps: UInt64
    public let kind: ConnectionConstraintKind
    public let source: EvidenceSource

    public init(label: String, maximumSpeedBps: UInt64, kind: ConnectionConstraintKind, source: EvidenceSource) {
        self.label = label
        self.maximumSpeedBps = maximumSpeedBps
        self.kind = kind
        self.source = source
    }
}

public enum ConnectionCause: String, Codable, Hashable, Sendable {
    case none
    case hub
    case connectionChain
    case unknown
    case cable
    case bridge
    case port
    case device
}

public struct CableCompatibilityResult: Codable, Hashable, Sendable {
    public let dataCompatible: Bool
    public let dataLimited: Bool
    public let powerCompatible: Bool
    public let powerLimited: Bool
    public let dataSummary: String
    public let powerSummary: String
    
    public init(dataCompatible: Bool, dataLimited: Bool, powerCompatible: Bool, powerLimited: Bool, dataSummary: String, powerSummary: String) {
        self.dataCompatible = dataCompatible
        self.dataLimited = dataLimited
        self.powerCompatible = powerCompatible
        self.powerLimited = powerLimited
        self.dataSummary = dataSummary
        self.powerSummary = powerSummary
    }
}

/// A ranked diagnostic conclusion. It describes a component category only
/// when the evidence supports it; a physical cable is never inferred as a
/// confirmed cause from link speed alone.
public struct ConnectionCauseAssessment: Codable, Hashable, Sendable {
    public let cause: ConnectionCause
    public let confidence: DiagnosticConfidence
    public let warningLevel: WarningLevel

    public init(cause: ConnectionCause, confidence: DiagnosticConfidence, warningLevel: WarningLevel) {
        self.cause = cause
        self.confidence = confidence
        self.warningLevel = warningLevel
    }
}

public struct ConnectionDiagnosis: Codable, Hashable, Sendable {
    public let currentLinkSpeedBps: UInt64?
    public let referenceMaxSpeedBps: UInt64?
    public let primaryCause: ConnectionCause
    public let confidence: DiagnosticConfidence
    public let warningLevel: WarningLevel
    public let causes: [ConnectionCauseAssessment]
    public let evidences: [DiagnosticEvidence]

    public init(
        currentLinkSpeedBps: UInt64?,
        referenceMaxSpeedBps: UInt64?,
        primaryCause: ConnectionCause,
        confidence: DiagnosticConfidence,
        warningLevel: WarningLevel,
        causes: [ConnectionCauseAssessment] = [],
        evidences: [DiagnosticEvidence]
    ) {
        self.currentLinkSpeedBps = currentLinkSpeedBps
        self.referenceMaxSpeedBps = referenceMaxSpeedBps
        self.primaryCause = primaryCause
        self.confidence = confidence
        self.warningLevel = warningLevel
        self.causes = causes
        self.evidences = evidences
    }
}

public enum ConnectionDiagnosisEngine {
    public static func cableCompatibilityCheck(deviceCapabilityBps: UInt64?, negotiatedBps: UInt64?, powerRequirementWatts: Double?, powerCapabilityWatts: Double?) -> CableCompatibilityResult {
        let dataLimited = (deviceCapabilityBps != nil && negotiatedBps != nil) ? negotiatedBps! < deviceCapabilityBps! : false
        let powerLimited = (powerRequirementWatts != nil && powerCapabilityWatts != nil) ? powerCapabilityWatts! < powerRequirementWatts! : false
        return CableCompatibilityResult(
            dataCompatible: true,
            dataLimited: dataLimited,
            powerCompatible: true,
            powerLimited: powerLimited,
            dataSummary: dataLimited ? "Data limited" : "Data OK",
            powerSummary: powerLimited ? "Power limited" : "Power OK"
        )
    }

    public static func analyze(
        currentLinkSpeedBps: UInt64?,
        referenceMaxSpeedBps: UInt64?,
        constraints: [ConnectionConstraint]
    ) -> ConnectionDiagnosis {
        var evidences: [DiagnosticEvidence] = []
        if let currentLinkSpeedBps {
            evidences.append(DiagnosticEvidence(
                label: "Velocità link negoziata",
                value: TransferSpeedFormatter.linkSpeed(currentLinkSpeedBps),
                source: .ioRegistryObserved
            ))
        }
        if let referenceMaxSpeedBps {
            evidences.append(DiagnosticEvidence(
                label: "Velocità di riferimento",
                value: TransferSpeedFormatter.linkSpeed(referenceMaxSpeedBps),
                source: .ioRegistryObserved
            ))
        }

        guard let currentLinkSpeedBps else {
            return ConnectionDiagnosis(
                currentLinkSpeedBps: nil,
                referenceMaxSpeedBps: referenceMaxSpeedBps,
                primaryCause: .unknown,
                confidence: .insufficientEvidence,
                warningLevel: .info,
                causes: [ConnectionCauseAssessment(cause: .unknown, confidence: .insufficientEvidence, warningLevel: .info)],
                evidences: evidences + [DiagnosticEvidence(label: "Link", source: .unavailable)]
            )
        }

        if let referenceMaxSpeedBps, currentLinkSpeedBps >= referenceMaxSpeedBps {
            return ConnectionDiagnosis(
                currentLinkSpeedBps: currentLinkSpeedBps,
                referenceMaxSpeedBps: referenceMaxSpeedBps,
                primaryCause: .device,
                confidence: .confirmed,
                warningLevel: .info,
                causes: [ConnectionCauseAssessment(cause: .device, confidence: .confirmed, warningLevel: .info)],
                evidences: evidences
            )
        }

        if let referenceMaxSpeedBps, currentLinkSpeedBps < referenceMaxSpeedBps {
            let observedConstraints = constraints
                .filter { $0.maximumSpeedBps <= currentLinkSpeedBps }
                .sorted { $0.maximumSpeedBps < $1.maximumSpeedBps }

            if let limiter = observedConstraints.first {
                let cause: ConnectionCause
                switch limiter.kind {
                case .hub: cause = .hub
                case .controller: cause = .bridge
                case .port: cause = .port
                case .device: cause = .device
                case .unknown: cause = .connectionChain
                }
                
                evidences.append(DiagnosticEvidence(
                    label: limiter.label,
                    value: TransferSpeedFormatter.linkSpeed(limiter.maximumSpeedBps),
                    source: limiter.source
                ))
                return ConnectionDiagnosis(
                    currentLinkSpeedBps: currentLinkSpeedBps,
                    referenceMaxSpeedBps: referenceMaxSpeedBps,
                    primaryCause: cause,
                    confidence: .confirmed,
                    warningLevel: .critical,
                    causes: [ConnectionCauseAssessment(cause: cause, confidence: .confirmed, warningLevel: .critical)],
                    evidences: evidences
                )
            }

            evidences.append(DiagnosticEvidence(
                label: "Causa fisica della limitazione",
                value: "Cavo, porta, adattatore o negoziazione",
                source: .inferred
            ))
            return ConnectionDiagnosis(
                currentLinkSpeedBps: currentLinkSpeedBps,
                referenceMaxSpeedBps: referenceMaxSpeedBps,
                primaryCause: .cable,
                confidence: .possible,
                warningLevel: .attention,
                causes: [ConnectionCauseAssessment(cause: .cable, confidence: .possible, warningLevel: .attention)],
                evidences: evidences
            )
        }

        return ConnectionDiagnosis(
            currentLinkSpeedBps: currentLinkSpeedBps,
            referenceMaxSpeedBps: referenceMaxSpeedBps,
            primaryCause: .none,
            confidence: DiagnosticConfidence.from(evidence: evidences),
            warningLevel: .info,
            causes: [],
            evidences: evidences
        )
    }
}
