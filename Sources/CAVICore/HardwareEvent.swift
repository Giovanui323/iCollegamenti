import Foundation

/// Minimal, privacy-preserving snapshot used to detect hardware changes
/// between two IORegistry refreshes.
public struct HardwareConnectionState: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let linkSpeedBps: UInt64?
    public let protocolName: String?
    public let isMounted: Bool

    public init(
        id: String,
        displayName: String,
        linkSpeedBps: UInt64?,
        protocolName: String?,
        isMounted: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.linkSpeedBps = linkSpeedBps
        self.protocolName = protocolName
        self.isMounted = isMounted
    }
}

public enum HardwareEventKind: String, Codable, CaseIterable, Hashable, Sendable {
    case connected
    case disconnected
    case mounted
    case unmounted
    case linkRenegotiated
    case protocolChanged
    case systemSleep
    case systemWake
    case benchmarkStarted
    case benchmarkCompleted
    case benchmarkFailed
}

public struct HardwareEvent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let kind: HardwareEventKind
    public let connectionID: String
    public let displayName: String
    public let linkSpeedBps: UInt64?
    public let previousLinkSpeedBps: UInt64?
    public let protocolName: String?
    public let previousProtocolName: String?
    public let detail: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: HardwareEventKind,
        connectionID: String,
        displayName: String,
        linkSpeedBps: UInt64? = nil,
        previousLinkSpeedBps: UInt64? = nil,
        protocolName: String? = nil,
        previousProtocolName: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.connectionID = connectionID
        self.displayName = displayName
        self.linkSpeedBps = linkSpeedBps
        self.previousLinkSpeedBps = previousLinkSpeedBps
        self.protocolName = protocolName
        self.previousProtocolName = previousProtocolName
        self.detail = detail
    }
}

public enum HardwareEventDetector {
    /// Compares opaque connection snapshots. New connections are emitted first,
    /// then removals and negotiated-link changes in a stable order.
    public static func changes(
        from previous: [HardwareConnectionState],
        to current: [HardwareConnectionState],
        timestamp: Date = Date()
    ) -> [HardwareEvent] {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        var events: [HardwareEvent] = []

        for state in current.filter({ previousByID[$0.id] == nil }).sorted(by: { $0.id < $1.id }) {
            events.append(HardwareEvent(
                timestamp: timestamp,
                kind: .connected,
                connectionID: state.id,
                displayName: state.displayName,
                linkSpeedBps: state.linkSpeedBps,
                protocolName: state.protocolName
            ))
        }

        for state in previous.filter({ currentByID[$0.id] == nil }).sorted(by: { $0.id < $1.id }) {
            events.append(HardwareEvent(
                timestamp: timestamp,
                kind: .disconnected,
                connectionID: state.id,
                displayName: state.displayName,
                linkSpeedBps: state.linkSpeedBps,
                protocolName: state.protocolName
            ))
        }

        for currentState in current.sorted(by: { $0.id < $1.id }) {
            guard let previousState = previousByID[currentState.id] else { continue }
            if currentState.linkSpeedBps != previousState.linkSpeedBps {
                events.append(HardwareEvent(
                    timestamp: timestamp,
                    kind: .linkRenegotiated,
                    connectionID: currentState.id,
                    displayName: currentState.displayName,
                    linkSpeedBps: currentState.linkSpeedBps,
                    previousLinkSpeedBps: previousState.linkSpeedBps,
                    protocolName: currentState.protocolName,
                    previousProtocolName: previousState.protocolName
                ))
            }
            if currentState.protocolName != previousState.protocolName {
                events.append(HardwareEvent(
                    timestamp: timestamp,
                    kind: .protocolChanged,
                    connectionID: currentState.id,
                    displayName: currentState.displayName,
                    linkSpeedBps: currentState.linkSpeedBps,
                    previousLinkSpeedBps: previousState.linkSpeedBps,
                    protocolName: currentState.protocolName,
                    previousProtocolName: previousState.protocolName
                ))
            }
            if currentState.isMounted != previousState.isMounted {
                events.append(HardwareEvent(
                    timestamp: timestamp,
                    kind: currentState.isMounted ? .mounted : .unmounted,
                    connectionID: currentState.id,
                    displayName: currentState.displayName,
                    linkSpeedBps: currentState.linkSpeedBps,
                    protocolName: currentState.protocolName
                ))
            }
        }
        return events
    }
}

/// Small, deterministic helpers for the locally persisted event buffer.
public enum HardwareEventHistory {
    public static func bounded(_ events: [HardwareEvent], limit: Int) -> [HardwareEvent] {
        guard limit > 0 else { return [] }
        return Array(events.prefix(limit))
    }
}

public struct StabilityPenaltyItem: Sendable, Hashable {
    public let kind: HardwareEventKind
    public let count: Int
    public let totalDeduction: Int

    public init(kind: HardwareEventKind, count: Int, totalDeduction: Int) {
        self.kind = kind
        self.count = count
        self.totalDeduction = totalDeduction
    }
}

/// A score exists only after there is at least one local observation for the
/// device. It communicates observed stability, never long-term reliability.
public enum EventStabilityScorer {
    public static func score(for events: [HardwareEvent]) -> Int? {
        guard !events.isEmpty else { return nil }
        let penalty = penaltyBreakdown(for: events).reduce(0) { $0 + $1.totalDeduction }
        return max(0, 100 - penalty)
    }

    public static func penaltyBreakdown(for events: [HardwareEvent]) -> [StabilityPenaltyItem] {
        guard !events.isEmpty else { return [] }
        var unmountedIDs = Set<String>()
        var abruptDisconnectCount = 0
        var linkRenegotiationCount = 0
        var protocolChangeCount = 0
        var benchmarkFailedCount = 0

        // Process in chronological order (oldest to newest)
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch event.kind {
            case .unmounted:
                unmountedIDs.insert(event.connectionID)
            case .mounted, .connected:
                unmountedIDs.remove(event.connectionID)
            case .disconnected:
                if unmountedIDs.contains(event.connectionID) {
                    // Safe disconnect after clean unmount: no penalty
                    unmountedIDs.remove(event.connectionID)
                } else {
                    // Abrupt / unexpected disconnect
                    abruptDisconnectCount += 1
                }
            case .linkRenegotiated:
                linkRenegotiationCount += 1
            case .protocolChanged:
                protocolChangeCount += 1
            case .benchmarkFailed:
                benchmarkFailedCount += 1
            case .systemSleep, .systemWake, .benchmarkStarted, .benchmarkCompleted:
                break
            }
        }

        var items: [StabilityPenaltyItem] = []
        if abruptDisconnectCount > 0 {
            items.append(StabilityPenaltyItem(kind: .disconnected, count: abruptDisconnectCount, totalDeduction: abruptDisconnectCount * 20))
        }
        if linkRenegotiationCount > 0 {
            items.append(StabilityPenaltyItem(kind: .linkRenegotiated, count: linkRenegotiationCount, totalDeduction: linkRenegotiationCount * 10))
        }
        if protocolChangeCount > 0 {
            items.append(StabilityPenaltyItem(kind: .protocolChanged, count: protocolChangeCount, totalDeduction: protocolChangeCount * 5))
        }
        if benchmarkFailedCount > 0 {
            items.append(StabilityPenaltyItem(kind: .benchmarkFailed, count: benchmarkFailedCount, totalDeduction: benchmarkFailedCount * 8))
        }
        return items
    }
}
