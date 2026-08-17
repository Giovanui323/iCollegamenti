import Foundation

public struct HDMISignalConfiguration: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let refreshRate: Double
    public let bitDepth: Int
    public let chroma: ChromaSubsampling
    public let isHDRActive: Bool
    public let isDSCActive: Bool
    public let isVRRActive: Bool
    public let transportType: String?
    public let bandwidthRequirement: HDMIBandwidthRequirement
    
    public init(width: Int, height: Int, refreshRate: Double, bitDepth: Int, chroma: ChromaSubsampling, isHDRActive: Bool, isDSCActive: Bool, isVRRActive: Bool, transportType: String?, bandwidthRequirement: HDMIBandwidthRequirement) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.bitDepth = bitDepth
        self.chroma = chroma
        self.isHDRActive = isHDRActive
        self.isDSCActive = isDSCActive
        self.isVRRActive = isVRRActive
        self.transportType = transportType
        self.bandwidthRequirement = bandwidthRequirement
    }
    
    public var resolutionWidth: Int { width }
    public var resolutionHeight: Int { height }
    public var chromaSubsampling: ChromaSubsampling { chroma }
}

public struct HDMIFallbackDetection: Codable, Hashable, Sendable {
    public let requested: HDMISignalConfiguration?
    public let actual: HDMISignalConfiguration
    public let isFallback: Bool
    public let fallbackReasons: [String]
    
    public init(requested: HDMISignalConfiguration?, actual: HDMISignalConfiguration, isFallback: Bool, fallbackReasons: [String]) {
        self.requested = requested
        self.actual = actual
        self.isFallback = isFallback
        self.fallbackReasons = fallbackReasons
    }
}

public enum HDMICapabilityTestStatus: String, Codable, Hashable, Sendable {
    case pass, fail, skipped, untested
}

public struct HDMICapabilityTestEntry: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let modeDescription: String
    public let width: Int
    public let height: Int
    public let refreshRate: Double
    public let bitDepth: Int
    public let chroma: ChromaSubsampling
    public let isHDR: Bool
    public let bandwidthGbps: Double
    public let status: HDMICapabilityTestStatus
    public let durationSeconds: Double?
    public let disconnects: Int
    public let notes: String?
    
    public init(id: UUID, modeDescription: String, width: Int, height: Int, refreshRate: Double, bitDepth: Int, chroma: ChromaSubsampling, isHDR: Bool, bandwidthGbps: Double, status: HDMICapabilityTestStatus, durationSeconds: Double?, disconnects: Int, notes: String?) {
        self.id = id
        self.modeDescription = modeDescription
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.bitDepth = bitDepth
        self.chroma = chroma
        self.isHDR = isHDR
        self.bandwidthGbps = bandwidthGbps
        self.status = status
        self.durationSeconds = durationSeconds
        self.disconnects = disconnects
        self.notes = notes
    }
}

public struct HDMIStressTestResult: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let mode: String
    public let durationSeconds: Int
    public let disconnects: Int
    public let renegotiations: Int
    public let modeChanges: Int
    public let hdcpFailures: Int
    public let stabilityScore: Int
    public let events: [HDMIStressEvent]
    
    public init(id: UUID, mode: String, durationSeconds: Int, disconnects: Int, renegotiations: Int, modeChanges: Int, hdcpFailures: Int, stabilityScore: Int, events: [HDMIStressEvent]) {
        self.id = id
        self.mode = mode
        self.durationSeconds = durationSeconds
        self.disconnects = disconnects
        self.renegotiations = renegotiations
        self.modeChanges = modeChanges
        self.hdcpFailures = hdcpFailures
        self.stabilityScore = stabilityScore
        self.events = events
    }
}

public struct HDMIStressEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let eventType: HDMIStressEventType
    public let description: String
    
    public init(id: UUID, timestamp: Date, eventType: HDMIStressEventType, description: String) {
        self.id = id
        self.timestamp = timestamp
        self.eventType = eventType
        self.description = description
    }
}

public enum HDMIStressEventType: String, Codable, Hashable, Sendable {
    case disconnect, reconnect, modeChange, renegotiation, hdcpFailure, signalLoss, signalRestore
}
