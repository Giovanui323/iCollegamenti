import Foundation
import Observation
import CAVICore

struct DriveHealthSnapshot: Sendable {
    let smartStatus: SMARTStatus
    let rawSMARTStatus: String?
    let temperatureCelsius: Double?
    let remainingLifePercent: Int?
    let powerOnHours: Int?
    let powerCycleCount: Int?
    let totalBytesWritten: UInt64?
    let mediaErrorCount: Int?
    let unsafeShutdownCount: Int?
    let assessment: DriveHealthAssessment

    static let unavailable = DriveHealthSnapshot(
        smartStatus: .unavailable,
        rawSMARTStatus: nil,
        temperatureCelsius: nil,
        remainingLifePercent: nil,
        powerOnHours: nil,
        powerCycleCount: nil,
        totalBytesWritten: nil,
        mediaErrorCount: nil,
        unsafeShutdownCount: nil,
        assessment: DriveHealthScorer.assess(DriveHealthInput())
    )
}

@Observable
@MainActor
final class DriveHealthService {
    private(set) var snapshots: [String: DriveHealthSnapshot] = [:]
    private(set) var temperatureObservations: [String: [BenchmarkTemperatureObservation]] = [:]
    private let temperatureObservationLimit = 900

    func snapshot(for device: DriveDevice) -> DriveHealthSnapshot? {
        snapshots[device.bsdName]
    }

    /// Measurements remain in memory and are used only to annotate a benchmark
    /// session. They are intentionally not treated as long-term SMART history.
    func temperatureHistory(for device: DriveDevice, since: Date) -> [BenchmarkTemperatureObservation] {
        temperatureObservations[device.bsdName, default: []].filter { $0.timestamp >= since }
    }

    func refresh(_ device: DriveDevice) async {
        guard device.isStorageDevice, !device.bsdName.isEmpty else { return }
        let bsdName = device.bsdName
        let snapshot = await Self.readHealth(bsdName: bsdName)
        snapshots[bsdName] = snapshot
        if let temperature = snapshot.temperatureCelsius, temperature.isFinite {
            var observations = temperatureObservations[bsdName, default: []]
            observations.append(.init(timestamp: Date(), celsius: temperature))
            if observations.count > temperatureObservationLimit {
                observations.removeFirst(observations.count - temperatureObservationLimit)
            }
            temperatureObservations[bsdName] = observations
        }
    }

    private nonisolated static func readHealth(bsdName: String) async -> DriveHealthSnapshot {
        await Task.detached(priority: .utility) {
            let normalized = bsdName.replacingOccurrences(of: "/dev/", with: "")
            guard !normalized.isEmpty,
                  normalized.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                return .unavailable
            }
            do {
                guard let data = try run("/usr/sbin/diskutil", arguments: ["info", "-plist", normalized]) else {
                    return .unavailable
                }
                let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                let rawStatus = values?["SMARTStatus"] as? String
                var status = smartStatus(from: rawStatus)
                var temperature: Double?
                var remainingLife: Int?
                var powerOnHours: Int?
                var powerCycles: Int?
                var totalBytesWritten: UInt64?
                var mediaErrors: Int?
                var unsafeShutdowns: Int?

                if let smartctl = smartctlPath(),
                   let smartData = try run(smartctl, arguments: ["-a", "-j", "-n", "standby", "/dev/\(normalized)"], acceptsNonZeroExit: true),
                   let smart = try? JSONSerialization.jsonObject(with: smartData) as? [String: Any] {
                    if let passed = nestedValue(in: smart, path: ["smart_status", "passed"]) as? Bool {
                        status = passed ? .verified : .failing
                    }
                    temperature = number(nestedValue(in: smart, path: ["temperature", "current"]))
                    if let used = number(nestedValue(in: smart, path: ["nvme_smart_health_information_log", "percentage_used"])) {
                        remainingLife = max(0, min(100, 100 - Int(used.rounded())))
                    }
                    powerOnHours = number(nestedValue(in: smart, path: ["power_on_time", "hours"])).map { Int($0) }
                    powerCycles = number(smart["power_cycle_count"]).map { Int($0) }
                    totalBytesWritten = number(nestedValue(in: smart, path: ["nvme_smart_health_information_log", "data_units_written"])).map { UInt64(max(0, $0 * 512_000)) }
                    mediaErrors = number(nestedValue(in: smart, path: ["nvme_smart_health_information_log", "media_errors"])).map { Int($0) }
                    unsafeShutdowns = number(nestedValue(in: smart, path: ["nvme_smart_health_information_log", "unsafe_shutdowns"])).map { Int($0) }
                }

                let assessment = DriveHealthScorer.assess(DriveHealthInput(
                    smartStatus: status,
                    temperatureCelsius: temperature,
                    remainingLifePercent: remainingLife,
                    mediaErrorCount: mediaErrors
                ))
                return DriveHealthSnapshot(
                    smartStatus: status,
                    rawSMARTStatus: rawStatus,
                    temperatureCelsius: temperature,
                    remainingLifePercent: remainingLife,
                    powerOnHours: powerOnHours,
                    powerCycleCount: powerCycles,
                    totalBytesWritten: totalBytesWritten,
                    mediaErrorCount: mediaErrors,
                    unsafeShutdownCount: unsafeShutdowns,
                    assessment: assessment
                )
            } catch {
                return .unavailable
            }
        }.value
    }

    private nonisolated static func run(
        _ executable: String,
        arguments: [String],
        acceptsNonZeroExit: Bool = false
    ) throws -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard acceptsNonZeroExit || process.terminationStatus == 0 else { return nil }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private nonisolated static func smartctlPath() -> String? {
        ["/opt/homebrew/sbin/smartctl", "/usr/local/sbin/smartctl", "/usr/sbin/smartctl"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func nestedValue(in dictionary: [String: Any], path: [String]) -> Any? {
        path.dropFirst().reduce(dictionary[path.first ?? ""]) { partial, key in
            (partial as? [String: Any])?[key]
        }
    }

    private nonisolated static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    private nonisolated static func smartStatus(from rawStatus: String?) -> SMARTStatus {
        switch rawStatus?.lowercased() {
        case "verified": .verified
        case "failing": .failing
        default: .unavailable
        }
    }
}
