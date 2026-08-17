import Foundation

public enum GuidedDiagnosticMode: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case driveIsSlow
    case cableIsGood
    case ssdIsHealthy
    case dockOrHub

    public var id: String { rawValue }

    public var requiresStorage: Bool {
        self == .driveIsSlow || self == .ssdIsHealthy
    }

    public var includesBenchmark: Bool {
        self == .driveIsSlow || self == .cableIsGood || self == .ssdIsHealthy
    }

    public var includesPowerCheck: Bool {
        self == .cableIsGood || self == .dockOrHub
    }

    public var includesTopologyCheck: Bool {
        self == .driveIsSlow || self == .cableIsGood || self == .dockOrHub
    }
}
