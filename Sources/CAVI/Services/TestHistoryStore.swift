import Foundation
import CAVICore

/// Persists cable test results and reference device profiles locally.
/// Data is stored in ~/Library/Application Support/CAVI/ as JSON files.
/// No data ever leaves the Mac - all storage is fully local.
@Observable
@MainActor
public final class TestHistoryStore {
    public var testResults: [CableTestResult] = []
    public var referenceDevices: [ReferenceDevice] = []
    public var cableProfiles: [CableProfile] = []
    public var advancedBenchmarkRecords: [AdvancedBenchmarkRecord] = []
    public var deviceHistory: [DeviceHistoryEntry] = []
    public private(set) var persistenceError: String?
    
    private let fileManager = FileManager.default
    
    private var baseDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let primaryURL = appSupport.appendingPathComponent("iCollegamenti")
        let legacyURL = appSupport.appendingPathComponent("CAVI")
        if !fileManager.fileExists(atPath: primaryURL.path) && fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }
        return primaryURL
    }
    
    private var historyFileURL: URL {
        baseDirectoryURL.appendingPathComponent("history.json")
    }
    
    private var referencesFileURL: URL {
        baseDirectoryURL.appendingPathComponent("references.json")
    }

    private var cablesFileURL: URL {
        baseDirectoryURL.appendingPathComponent("cables.json")
    }

    private var advancedBenchmarksFileURL: URL {
        baseDirectoryURL.appendingPathComponent("advanced-benchmarks.json")
    }

    private var deviceHistoryFileURL: URL {
        baseDirectoryURL.appendingPathComponent("device-history.json")
    }
    
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public enum ImportError: LocalizedError {
        case invalidFile
        public var errorDescription: String? { "Il file non contiene una cronologia CAVI valida." }
    }
    
    public struct DeviceHistoryEntry: Codable, Hashable, Sendable, Identifiable {
        public let id: UUID
        public let timestamp: Date
        public let deviceName: String
        public let vendorID: Int?
        public let productID: Int?
        public let serialNumber: String?
        public let negotiatedSpeedBps: UInt64?
        public let benchmarkReadMBps: Double?
        public let benchmarkWriteMBps: Double?
        public let healthScore: Int?
        public let temperatureCelsius: Double?
    }
    
    public init() {
        load()
    }
    
    // MARK: - Directory Management
    
    private func ensureDirectoryExists() {
        if !fileManager.fileExists(atPath: baseDirectoryURL.path) {
            try? fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Test Results
    
    public func saveTestResult(_ result: CableTestResult) {
        testResults.insert(result, at: 0) // newest first
        touchCable(result.cableID)
        save()
    }

    @discardableResult
    public func upsertAutomaticResult(for device: DriveDevice, fingerprint: String) -> UUID {
        if let existing = latestResult(forConnection: fingerprint) { return existing.id }
        let defaultLabel = device.storageConnectionKind == .integratedSDReader
            ? "\(device.displayName) — \(device.storageConnectionKind.connectionDescription)"
            : "\(device.displayName) — \(device.speedRating.connectionType)"
        let topologyDescription = device.storageConnectionKind.supportsUSBTopology
            ? USBTopologyService.topologyDescription(for: device)
            : device.storageConnectionKind.connectionDescription
        let result = CableTestResult(cableLabel: defaultLabel, deviceName: device.displayName, deviceVendorID: device.vendorID, deviceProductID: device.productID, deviceSerialNumber: device.serialNumber, linkSpeedBps: device.negotiatedSpeedBps ?? 0, topologyDescription: topologyDescription, connectionFingerprint: fingerprint)
        saveTestResult(result)
        return result.id
    }

    public func attachBenchmark(_ benchmark: BenchmarkResult, to resultID: UUID) {
        guard let index = testResults.firstIndex(where: { $0.id == resultID }) else { return }
        let old = testResults[index]
        testResults[index] = CableTestResult(id: old.id, cableLabel: old.cableLabel, timestamp: benchmark.timestamp, deviceName: old.deviceName, deviceVendorID: old.deviceVendorID, deviceProductID: old.deviceProductID, deviceSerialNumber: old.deviceSerialNumber, linkSpeedBps: old.linkSpeedBps, benchmarkReadMBps: benchmark.sequentialReadMBps, benchmarkWriteMBps: benchmark.sequentialWriteMBps, portInfo: old.portInfo, hubInfo: old.hubInfo, userNotes: old.userNotes, topologyDescription: old.topologyDescription, connectionFingerprint: old.connectionFingerprint, cableID: old.cableID, category: old.category)
        save()
    }

    public func saveAdvancedBenchmark(_ result: AdvancedBenchmarkResult, for device: DriveDevice, fingerprint: String) {
        advancedBenchmarkRecords.insert(
            AdvancedBenchmarkRecord(
                connectionFingerprint: fingerprint,
                deviceName: device.displayName,
                result: result
            ),
            at: 0
        )
        save()
    }

    public func recordDeviceSnapshot(_ device: DriveDevice, benchmark: BenchmarkResult?, health: DriveHealthAssessment?, temperature: Double?) {
        let entry = DeviceHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            deviceName: device.displayName,
            vendorID: device.vendorID,
            productID: device.productID,
            serialNumber: device.serialNumber,
            negotiatedSpeedBps: device.negotiatedSpeedBps,
            benchmarkReadMBps: benchmark?.sequentialReadMBps,
            benchmarkWriteMBps: benchmark?.sequentialWriteMBps,
            healthScore: health?.score,
            temperatureCelsius: temperature
        )
        deviceHistory.insert(entry, at: 0)
        save()
    }
    
    public func deviceHistory(for device: DriveDevice) -> [DeviceHistoryEntry] {
        deviceHistory.filter { entry in
            if let s1 = entry.serialNumber, let s2 = device.serialNumber, !s1.isEmpty, !s2.isEmpty {
                return s1 == s2
            }
            if let v1 = entry.vendorID, let v2 = device.vendorID,
               let p1 = entry.productID, let p2 = device.productID {
                return v1 == v2 && p1 == p2
            }
            return false
        }
    }
    
    public func deleteTestResult(id: UUID) {
        testResults.removeAll { $0.id == id }
        save()
    }
    
    public func deleteTestResults(ids: Set<UUID>) {
        testResults.removeAll { ids.contains($0.id) }
        save()
    }
    
    public func clearAllTestResults() {
        testResults.removeAll()
        advancedBenchmarkRecords.removeAll()
        deviceHistory.removeAll()
        save()
    }
    
    public func renameTestResult(id: UUID, newLabel: String) {
        if let index = testResults.firstIndex(where: { $0.id == id }) {
            let old = testResults[index]
            testResults[index] = CableTestResult(
                id: old.id,
                cableLabel: newLabel,
                timestamp: old.timestamp,
                deviceName: old.deviceName,
                deviceVendorID: old.deviceVendorID,
                deviceProductID: old.deviceProductID,
                deviceSerialNumber: old.deviceSerialNumber,
                linkSpeedBps: old.linkSpeedBps,
                benchmarkReadMBps: old.benchmarkReadMBps,
                benchmarkWriteMBps: old.benchmarkWriteMBps,
                portInfo: old.portInfo,
                hubInfo: old.hubInfo,
                userNotes: old.userNotes,
                topologyDescription: old.topologyDescription,
                connectionFingerprint: old.connectionFingerprint,
                cableID: old.cableID,
                category: old.category
            )
            save()
        }
    }

    public func updateNotes(id: UUID, notes: String) {
        guard let index = testResults.firstIndex(where: { $0.id == id }) else { return }
        let old = testResults[index]
        let clean = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        testResults[index] = CableTestResult(id: old.id, cableLabel: old.cableLabel, timestamp: old.timestamp, deviceName: old.deviceName, deviceVendorID: old.deviceVendorID, deviceProductID: old.deviceProductID, deviceSerialNumber: old.deviceSerialNumber, linkSpeedBps: old.linkSpeedBps, benchmarkReadMBps: old.benchmarkReadMBps, benchmarkWriteMBps: old.benchmarkWriteMBps, portInfo: old.portInfo, hubInfo: old.hubInfo, userNotes: clean.isEmpty ? nil : clean, topologyDescription: old.topologyDescription, connectionFingerprint: old.connectionFingerprint, cableID: old.cableID, category: old.category)
        save()
    }

    // MARK: - Cable Catalog

    public func createCable(named name: String) -> CableProfile {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var profile = CableProfile(name: cleanName)
        while cableProfiles.contains(where: { $0.code == profile.code }) {
            profile = CableProfile(name: cleanName)
        }
        cableProfiles.insert(profile, at: 0)
        save()
        return profile
    }

    public func cableProfile(id: UUID?) -> CableProfile? {
        guard let id else { return nil }
        return cableProfiles.first(where: { $0.id == id })
    }

    public func renameCable(id: UUID, newName: String) {
        guard let index = cableProfiles.firstIndex(where: { $0.id == id }) else { return }
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        cableProfiles[index].name = cleanName
        cableProfiles[index].lastUsedAt = Date()
        save()
    }

    public func confirmCable(_ id: UUID, forConnection fingerprint: String?) {
        guard let index = cableProfiles.firstIndex(where: { $0.id == id }) else { return }
        if let fingerprint, !fingerprint.isEmpty {
            cableProfiles[index].confirmedConnectionFingerprints.insert(fingerprint)
        }
        cableProfiles[index].lastUsedAt = Date()
        save()
    }

    /// Returns a candidate only when exactly one user-confirmed cable matches.
    /// The caller must ask for confirmation before making a new association.
    public func suggestedCable(forConnection fingerprint: String) -> CableProfile? {
        let matches = cableProfiles.filter { $0.confirmedConnectionFingerprints.contains(fingerprint) }
        return matches.count == 1 ? matches[0] : nil
    }

    public func assignCable(_ cableID: UUID?, toResult resultID: UUID) {
        guard let index = testResults.firstIndex(where: { $0.id == resultID }) else { return }
        let old = testResults[index]
        testResults[index] = CableTestResult(
            id: old.id,
            cableLabel: old.cableLabel,
            timestamp: old.timestamp,
            deviceName: old.deviceName,
            deviceVendorID: old.deviceVendorID,
            deviceProductID: old.deviceProductID,
            deviceSerialNumber: old.deviceSerialNumber,
            linkSpeedBps: old.linkSpeedBps,
            benchmarkReadMBps: old.benchmarkReadMBps,
            benchmarkWriteMBps: old.benchmarkWriteMBps,
            portInfo: old.portInfo,
            hubInfo: old.hubInfo,
            userNotes: old.userNotes,
            topologyDescription: old.topologyDescription,
            connectionFingerprint: old.connectionFingerprint,
            cableID: cableID,
            category: old.category
        )
        touchCable(cableID)
        save()
    }

    public func importResults(from data: Data) throws -> Int {
        guard let imported = try? decoder.decode([CableTestResult].self, from: data) else { throw ImportError.invalidFile }
        let existingIDs = Set(testResults.map(\.id))
        let newResults = imported.filter { !existingIDs.contains($0.id) }
        guard !newResults.isEmpty else { return 0 }
        testResults.insert(contentsOf: newResults, at: 0)
        save()
        return newResults.count
    }
    
    // MARK: - Reference Devices
    
    public func addReferenceDevice(_ device: ReferenceDevice) {
        // Update if same VID+PID+Serial exists, otherwise add
        if let index = referenceDevices.firstIndex(where: {
            $0.vendorID == device.vendorID &&
            $0.productID == device.productID &&
            $0.serialNumber == device.serialNumber
        }) {
            referenceDevices[index] = device
        } else {
            referenceDevices.append(device)
        }
        save()
    }
    
    public func updateReferenceDevice(_ device: ReferenceDevice) {
        if let index = referenceDevices.firstIndex(where: { $0.id == device.id }) {
            referenceDevices[index] = device
            save()
        }
    }
    
    public func findReferenceDevice(for device: DriveDevice) -> ReferenceDevice? {
        return referenceDevices.first { $0.matches(device: device) }
    }
    
    /// Creates or updates a reference device from a DriveDevice, recording its current speed.
    public func registerAsReference(_ device: DriveDevice) -> ReferenceDevice {
        if let existing = findReferenceDevice(for: device) {
            // Update max observed speed if current is higher
            let maxSpeed = max(existing.maxObservedSpeedBps, device.negotiatedSpeedBps ?? 0)
            let updated = ReferenceDevice(
                id: existing.id,
                vendorID: device.vendorID,
                productID: device.productID,
                serialNumber: device.serialNumber,
                vendorName: device.vendorName,
                productName: device.productName,
                maxObservedSpeedBps: maxSpeed,
                maxBenchmarkReadMBps: existing.maxBenchmarkReadMBps,
                maxBenchmarkWriteMBps: existing.maxBenchmarkWriteMBps,
                dateAdded: existing.dateAdded,
                dateLastSeen: Date()
            )
            updateReferenceDevice(updated)
            return updated
        } else {
            let ref = ReferenceDevice(
                vendorID: device.vendorID,
                productID: device.productID,
                serialNumber: device.serialNumber,
                vendorName: device.vendorName,
                productName: device.productName,
                maxObservedSpeedBps: device.negotiatedSpeedBps ?? 0,
                dateAdded: Date(),
                dateLastSeen: Date()
            )
            addReferenceDevice(ref)
            return ref
        }
    }
    
    // MARK: - Cable Analysis
    
    public func getResultsForCable(label: String) -> [CableTestResult] {
        return testResults.filter { $0.cableLabel == label }
    }

    public func results(forCategory category: CableCategory?) -> [CableTestResult] {
        guard let category else { return testResults }
        return testResults.filter { $0.category == category }
    }

    public func hasSeenConnection(_ fingerprint: String) -> Bool {
        testResults.contains { $0.connectionFingerprint == fingerprint }
    }

    public func latestResult(forConnection fingerprint: String) -> CableTestResult? {
        testResults
            .filter { $0.connectionFingerprint == fingerprint }
            .max { $0.timestamp < $1.timestamp }
    }

    public func savedResult(forConnection fingerprint: String) -> CableTestResult? {
        latestResult(forConnection: fingerprint)
    }
    
    public func matchesDevice(_ result: CableTestResult, device: DriveDevice) -> Bool {
        if let serial = device.serialNumber, !serial.isEmpty, let s2 = result.deviceSerialNumber, !s2.isEmpty {
            return serial == s2
        }
        if let vid = device.vendorID, let pid = device.productID,
           let v2 = result.deviceVendorID, let p2 = result.deviceProductID {
            return vid == v2 && pid == p2
        }
        if !result.deviceName.isEmpty && result.deviceName == device.displayName {
            return true
        }
        return false
    }

    public func benchmarkHistory(for device: DriveDevice) -> [CableTestResult] {
        testResults.filter { r in
            (r.benchmarkReadMBps != nil || r.benchmarkWriteMBps != nil) &&
            matchesDevice(r, device: device)
        }
    }

    public func advancedBenchmarkHistory(for device: DriveDevice) -> [AdvancedBenchmarkRecord] {
        advancedBenchmarkRecords.filter { r in
            r.deviceName == device.displayName
        }
    }

    public func savedResult(for device: DriveDevice) -> CableTestResult? {
        if let serial = device.serialNumber, !serial.isEmpty {
            if let match = testResults.first(where: {
                $0.deviceSerialNumber == serial &&
                ($0.deviceVendorID == device.vendorID || device.vendorID == nil) &&
                ($0.deviceProductID == device.productID || device.productID == nil)
            }) {
                return match
            }
        }
        if let vid = device.vendorID, let pid = device.productID {
            if let match = testResults.first(where: {
                $0.deviceVendorID == vid && $0.deviceProductID == pid
            }) {
                return match
            }
        }
        let fingerprint = device.recognitionFingerprint(connectedAt: Date())
        return latestResult(forConnection: fingerprint)
    }
    
    public func analyzeStability(forCable label: String) -> CableStabilityAnalysis {
        let results = getResultsForCable(label: label)
        return CableStabilityAnalysis(cableLabel: label, results: results)
    }
    
    // MARK: - Export
    
    public func exportCSV() -> String {
        var csv = "Codice Cavo,Cavo,Misura,Benchmark Lettura MB/s,Benchmark Scrittura MB/s,Dispositivo,Data,Hub,Porta,Note\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        for r in testResults {
            let date = dateFormatter.string(from: r.timestamp)
            let read = r.benchmarkReadMBps != nil ? String(format: "%.1f", r.benchmarkReadMBps!) : ""
            let write = r.benchmarkWriteMBps != nil ? String(format: "%.1f", r.benchmarkWriteMBps!) : ""
            csv += [
                CSVEncoder.field(cableProfile(id: r.cableID)?.code ?? ""),
                CSVEncoder.field(r.cableLabel),
                CSVEncoder.field(r.primaryMeasurement.value),
                read,
                write,
                CSVEncoder.field(r.deviceName),
                CSVEncoder.field(date),
                CSVEncoder.field(r.hubInfo ?? ""),
                CSVEncoder.field(r.portInfo ?? ""),
                CSVEncoder.field(r.userNotes ?? "")
            ].joined(separator: ",") + "\n"
        }
        
        return csv
    }
    
    public func exportJSON() -> String {
        guard let data = try? encoder.encode(testResults),
              let redacted = SharedExportSanitizer.redactJSON(data) else {
            return "[]"
        }
        return String(data: redacted, encoding: .utf8) ?? "[]"
    }

    public func exportDiagnosticJSON(events: [HardwareEvent] = []) -> String {
        struct DiagnosticExport: Codable {
            let generatedAt: Date
            let operatingSystem: String
            let results: [CableTestResult]
            let advancedBenchmarks: [AdvancedBenchmarkRecord]
            let events: [HardwareEvent]
        }
        let export = DiagnosticExport(
            generatedAt: Date(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            results: testResults,
            advancedBenchmarks: advancedBenchmarkRecords,
            events: events
        )
        guard let data = try? encoder.encode(export),
              let redacted = SharedExportSanitizer.redactJSON(data) else {
            return "{}"
        }
        return String(data: redacted, encoding: .utf8) ?? "{}"
    }

    public func exportMarkdown(language: AppLanguage = .english, events: [HardwareEvent] = []) -> String {
        let rows = testResults.map { result in
            let unmeasured = language == .english ? "not measured" : "non misurata"
            let readLabel = language == .english ? "read" : "lettura"
            let writeLabel = language == .english ? "write" : "scrittura"
            let read = result.benchmarkReadMBps.map { String(format: "%.1f MB/s", $0) } ?? unmeasured
            let write = result.benchmarkWriteMBps.map { String(format: "%.1f MB/s", $0) } ?? unmeasured
            let code = cableProfile(id: result.cableID)?.code
            let title = code.map { "\($0) · \(result.cableLabel)" } ?? result.cableLabel
            return "- **\(title)** — \(result.linkSpeedFormatted), \(readLabel) \(read), \(writeLabel) \(write)"
        }.joined(separator: "\n")
        
        let title = language == .english ? "# iCollegamenti Report" : "# Report iCollegamenti"
        let note = language == .english 
            ? "Video requirements and potential bottlenecks are estimations: macOS does not physically certify the cable."
            : "I requisiti video e i possibili colli di bottiglia sono stime: macOS non certifica il cavo fisico."
        let section = language == .english ? "## Results" : "## Risultati"
        let advancedSection = language == .english ? "## Advanced benchmarks" : "## Benchmark avanzati"
        let advancedRows = advancedBenchmarkRecords.map { record in
            let workload = record.result.configuration.workload.rawValue
            let preset = ByteCountFormatter.string(fromByteCount: Int64(record.result.configuration.preset.sizeBytes), countStyle: .file)
            return "- **\(record.deviceName)** — \(workload), \(preset), \(record.timestamp.formatted(date: .abbreviated, time: .shortened))"
        }.joined(separator: "\n")
        let systemSection = language == .english ? "## System" : "## Sistema"
        let systemRows = language == .english
            ? "- Generated: \(Date().formatted(date: .abbreviated, time: .shortened))\n- macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n- Privacy: hardware identifiers are omitted from shareable JSON exports."
            : "- Generato: \(Date().formatted(date: .abbreviated, time: .shortened))\n- macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n- Privacy: gli identificativi hardware sono omessi dalle esportazioni JSON condivisibili."
        let eventSection = language == .english ? "## Event log" : "## Log eventi"
        let noEvents = language == .english ? "- No local hardware events were recorded." : "- Non sono stati registrati eventi hardware locali."
        let eventRows = events.isEmpty ? noEvents : events.map { event in
            let speed = event.linkSpeedBps.map { " — \(TransferSpeedFormatter.linkSpeed($0))" } ?? ""
            return "- \(event.timestamp.formatted(date: .abbreviated, time: .shortened)) — \(event.kind.rawValue) — \(event.displayName)\(speed)"
        }.joined(separator: "\n")
        let evidenceSection = language == .english ? "## Evidence and limits" : "## Evidenze e limiti"
        let evidenceRows = language == .english
            ? "- **Link and topology:** confirmed only when macOS exposes an I/O Registry value; otherwise unavailable.\n- **Benchmark:** measured directly by iCollegamenti with an exclusive temporary file.\n- **Power:** a battery-side estimate when macOS exposes voltage/current; it is not a USB-PD contract.\n- **Drive health:** SMART/temperature/wear are best effort and may be unavailable through an enclosure.\n- **Events:** observed locally while the app was running; they do not certify long-term cable reliability."
            : "- **Link e topologia:** confermati solo quando macOS espone un valore nel registro I/O; altrimenti non disponibili.\n- **Benchmark:** misurato direttamente da iCollegamenti con un file temporaneo esclusivo.\n- **Alimentazione:** stima lato batteria quando macOS espone tensione/corrente; non è un contratto USB-PD.\n- **Salute unità:** SMART/temperatura/usura sono best effort e possono non essere disponibili tramite un enclosure.\n- **Eventi:** osservati localmente mentre l’app era in esecuzione; non certificano l’affidabilità a lungo termine del cavo."
        
        return "\(title)\n\n\(note)\n\n\(systemSection)\n\n\(systemRows)\n\n\(section)\n\n\(rows)\n\n\(advancedSection)\n\n\(advancedRows)\n\n\(eventSection)\n\n\(eventRows)\n\n\(evidenceSection)\n\n\(evidenceRows)"
    }

    public func exportPlainText(language: AppLanguage = .english, events: [HardwareEvent] = []) -> String {
        exportMarkdown(language: language, events: events)
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "**", with: "")
    }
    
    // MARK: - Persistence
    
    public func load() {
        ensureDirectoryExists()
        
        if let data = try? Data(contentsOf: historyFileURL),
           let decoded = try? decoder.decode([CableTestResult].self, from: data) {
            testResults = decoded
        }
        
        if let data = try? Data(contentsOf: referencesFileURL),
           let decoded = try? decoder.decode([ReferenceDevice].self, from: data) {
            referenceDevices = decoded
        }

        if let data = try? Data(contentsOf: cablesFileURL),
           let decoded = try? decoder.decode([CableProfile].self, from: data) {
            cableProfiles = decoded
        }

        if let data = try? Data(contentsOf: advancedBenchmarksFileURL),
           let decoded = try? decoder.decode([AdvancedBenchmarkRecord].self, from: data) {
            advancedBenchmarkRecords = decoded
        }

        if let data = try? Data(contentsOf: deviceHistoryFileURL),
           let decoded = try? decoder.decode([DeviceHistoryEntry].self, from: data) {
            deviceHistory = decoded
        }
    }
    
    public func save() {
        ensureDirectoryExists()
        
        do {
            try encoder.encode(testResults).write(to: historyFileURL, options: .atomic)
            try encoder.encode(referenceDevices).write(to: referencesFileURL, options: .atomic)
            try encoder.encode(cableProfiles).write(to: cablesFileURL, options: .atomic)
            try encoder.encode(advancedBenchmarkRecords).write(to: advancedBenchmarksFileURL, options: .atomic)
            try encoder.encode(deviceHistory).write(to: deviceHistoryFileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Impossibile salvare i dati locali: \(error.localizedDescription)"
        }
    }

    private func touchCable(_ cableID: UUID?) {
        guard let cableID,
              let index = cableProfiles.firstIndex(where: { $0.id == cableID }) else { return }
        cableProfiles[index].lastUsedAt = Date()
    }
}
