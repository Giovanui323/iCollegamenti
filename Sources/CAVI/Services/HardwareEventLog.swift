import Foundation
import Observation
import AppKit
import CAVICore

@Observable
@MainActor
final class HardwareEventLog {
    private static let storageKey = "hardwareEventLog.v1"
    private let limit = 500

    private(set) var events: [HardwareEvent] = []
    private var latestStates: [HardwareConnectionState] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([HardwareEvent].self, from: data) {
            events = HardwareEventHistory.bounded(saved, limit: limit)
        }
        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.recordSystemEvent(.systemSleep) }
            },
            notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.recordSystemEvent(.systemWake) }
            }
        ]
    }

    func observe(_ devices: [DriveDevice]) {
        let states = devices.map(state(for:))
        let changes = HardwareEventDetector.changes(from: latestStates, to: states)
        latestStates = states
        append(changes)
    }

    func recordBenchmark(kind: HardwareEventKind, mountPath: String, detail: String? = nil) {
        guard [.benchmarkStarted, .benchmarkCompleted, .benchmarkFailed].contains(kind) else { return }
        let displayName = URL(fileURLWithPath: mountPath).lastPathComponent
        append([HardwareEvent(
            kind: kind,
            connectionID: "benchmark:\(mountPath)",
            displayName: displayName.isEmpty ? mountPath : displayName,
            detail: detail
        )])
    }

    func clear() {
        events = []
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    func exportPlainText() -> String {
        events.reversed().map { event in
            "\(event.timestamp.formatted(date: .numeric, time: .standard)) — \(eventDescription(event))"
        }
        .joined(separator: "\n")
    }

    func eventDescription(_ event: HardwareEvent) -> String {
        switch event.kind {
        case .connected:
            let link = event.linkSpeedBps.map(TransferSpeedFormatter.linkSpeed) ?? "link unavailable"
            return "\(event.displayName) connected (\(link))"
        case .disconnected:
            return "\(event.displayName) disconnected"
        case .mounted:
            return "\(event.displayName) mounted"
        case .unmounted:
            return "\(event.displayName) unmounted"
        case .linkRenegotiated:
            let old = event.previousLinkSpeedBps.map(TransferSpeedFormatter.linkSpeed) ?? "unknown"
            let new = event.linkSpeedBps.map(TransferSpeedFormatter.linkSpeed) ?? "unknown"
            return "\(event.displayName) link renegotiated: \(old) → \(new)"
        case .protocolChanged:
            return "\(event.displayName) protocol changed: \(event.previousProtocolName ?? "unknown") → \(event.protocolName ?? "unknown")"
        case .systemSleep:
            return "Mac entered sleep"
        case .systemWake:
            return "Mac woke from sleep"
        case .benchmarkStarted:
            return "Benchmark started for \(event.displayName)"
        case .benchmarkCompleted:
            return "Benchmark completed for \(event.displayName)"
        case .benchmarkFailed:
            return "Benchmark interrupted for \(event.displayName): \(event.detail ?? "unknown error")"
        }
    }

    /// Score based only on events observed while this app has been running.
    /// It is not a certification of long-term cable reliability.
    func stabilityScore(for device: DriveDevice) -> Int? {
        let id = connectionID(for: device)
        let relevant = events.filter { $0.connectionID == id || $0.connectionID == "benchmark:\(device.mountPath)" }
        return EventStabilityScorer.score(for: relevant)
    }

    func penaltyBreakdown(for device: DriveDevice) -> [StabilityPenaltyItem] {
        let id = connectionID(for: device)
        let relevant = events.filter { $0.connectionID == id || $0.connectionID == "benchmark:\(device.mountPath)" }
        return EventStabilityScorer.penaltyBreakdown(for: relevant)
    }

    func clear(for device: DriveDevice) {
        let id = connectionID(for: device)
        let benchID = "benchmark:\(device.mountPath)"
        events.removeAll { $0.connectionID == id || $0.connectionID == benchID }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func state(for device: DriveDevice) -> HardwareConnectionState {
        HardwareConnectionState(
            id: connectionID(for: device),
            displayName: device.displayName,
            linkSpeedBps: device.negotiatedSpeedBps,
            protocolName: device.protocol_,
            isMounted: device.isMountedVolume
        )
    }

    private func recordSystemEvent(_ kind: HardwareEventKind) {
        append([HardwareEvent(
            kind: kind,
            connectionID: "system",
            displayName: "Mac"
        )])
    }

    private func connectionID(for device: DriveDevice) -> String {
        if !device.bsdName.isEmpty { return "bsd:\(device.bsdName)" }
        if let locationID = device.locationID {
            return "location:\(locationID):\(device.vendorID ?? -1):\(device.productID ?? -1)"
        }
        return "peripheral:\(device.vendorID ?? -1):\(device.productID ?? -1):\(device.displayName)"
    }

    private func append(_ newEvents: [HardwareEvent]) {
        guard !newEvents.isEmpty else { return }
        events.insert(contentsOf: newEvents.reversed(), at: 0)
        events = HardwareEventHistory.bounded(events, limit: limit)
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
