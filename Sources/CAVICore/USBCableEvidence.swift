import Foundation

/// Raw, local observations obtained from one USB-C port controller. The values
/// describe only what the current Mac published; they are not a cable identity.
public struct USBPortRegistryRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let portName: String
    public let connectionActive: Bool
    public let activeCable: Bool?
    public let transports: [String]
    public let authorizationRequired: Bool
    public let authorizationStatus: String?
    public let overcurrentCount: Int?
    public let liquidDetected: Bool?
    public let cableIdentityProperties: [String: String]

    public init(
        id: String,
        portName: String,
        connectionActive: Bool,
        activeCable: Bool?,
        transports: [String],
        authorizationRequired: Bool,
        authorizationStatus: String?,
        overcurrentCount: Int?,
        liquidDetected: Bool?,
        cableIdentityProperties: [String: String]
    ) {
        self.id = id
        self.portName = portName
        self.connectionActive = connectionActive
        self.activeCable = activeCable
        self.transports = transports
        self.authorizationRequired = authorizationRequired
        self.authorizationStatus = authorizationStatus
        self.overcurrentCount = overcurrentCount
        self.liquidDetected = liquidDetected
        self.cableIdentityProperties = cableIdentityProperties
    }
}

public enum USBCableEvidenceAvailability: String, Codable, Hashable, Sendable {
    case available
    case unavailable
}

public enum USBCableEvidenceState: String, Codable, Hashable, Sendable {
    /// macOS published properties from a PD cable-side component (SOP'/SOP'').
    case cableIdentityObserved
    /// A connection is active but macOS did not publish cable-side PD properties.
    case connectedWithoutCableIdentity
    case inactive
}

public struct USBCableEvidencePort: Codable, Hashable, Sendable, Identifiable {
    public let record: USBPortRegistryRecord

    public init(record: USBPortRegistryRecord) {
        self.record = record
    }

    public var id: String { record.id }
    public var portName: String { record.portName }
    public var connectionActive: Bool { record.connectionActive }
    public var activeCable: Bool? { record.activeCable }
    public var transports: [String] { record.transports }
    public var authorizationRequired: Bool { record.authorizationRequired }
    public var authorizationStatus: String? { record.authorizationStatus }
    public var overcurrentCount: Int? { record.overcurrentCount }
    public var liquidDetected: Bool? { record.liquidDetected }
    public var cableIdentityProperties: [String: String] { record.cableIdentityProperties }

    public var state: USBCableEvidenceState {
        guard connectionActive else { return .inactive }
        return cableIdentityProperties.isEmpty ? .connectedWithoutCableIdentity : .cableIdentityObserved
    }

    /// The registry may contain a PD/e-marker response, but software cannot
    /// establish the cable's physical construction or Apple/MFi authenticity.
    public var isPhysicalCertification: Bool { false }

    public var evidenceSource: EvidenceSource { .ioRegistryObserved }

    public var hasObservedSafetyAttention: Bool {
        (overcurrentCount ?? 0) > 0 || liquidDetected == true
    }
}

public struct USBCableEvidenceSnapshot: Codable, Hashable, Sendable {
    public let availability: USBCableEvidenceAvailability
    public let ports: [USBCableEvidencePort]

    public var hasReadablePorts: Bool { !ports.isEmpty }

    public init(ports: [USBCableEvidencePort]) {
        self.ports = ports
        availability = ports.isEmpty ? .unavailable : .available
    }
}

public enum USBCableEvidenceBuilder {
    public static func make(from records: [USBPortRegistryRecord]) -> USBCableEvidenceSnapshot {
        let ports = records
            .map(USBCableEvidencePort.init(record:))
            .sorted { $0.portName.localizedStandardCompare($1.portName) == .orderedAscending }
        return USBCableEvidenceSnapshot(ports: ports)
    }
}
