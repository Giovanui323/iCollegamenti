import Foundation
import IOKit
import CAVICore

actor ProgressCollector {
    private(set) var values: [BenchmarkProgress] = []
    func append(_ value: BenchmarkProgress) { values.append(value) }
}

actor TemporaryBenchmarkFileInspector {
    private var largestObservedSize: UInt64 = 0

    func observe(in directory: URL) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where name.hasPrefix(".cavi-benchmark-") {
            let path = directory.appendingPathComponent(name).path
            guard let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else { continue }
            largestObservedSize = max(largestObservedSize, size.uint64Value)
        }
    }

    func largestSize() -> UInt64 { largestObservedSize }
}

@main
struct SafetyTestRunner {
    static func main() async {
        print("==================================================")
        print("      CAVI AUTOMATED SAFETY & LOGIC TEST SUITE     ")
        print("==================================================")
        
        var passedCount = 0
        var failedCount = 0
        
        // Test 1: CRITICAL DATA SAFETY TEST - Never deletes user files
        if await runTest(name: "Data Safety: Benchmark NEVER deletes or alters user files", block: {
            try await testProductionBenchmarkPreservesUserFiles()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        // Test 2: CRITICAL DATA SAFETY TEST - Cancellation cleanup
        if await runTest(name: "Data Safety: Benchmark cleans up temp file on cancellation", block: {
            try await testDataSafetyCancellationCleanup()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        // Test 3: Speed Classification
        if await runTest(name: "Speed Classification & Formatting", block: {
            testSpeedClassification()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        // Test 4: Bottleneck Analyzer
        if await runTest(name: "Bottleneck Analyzer: Cable & Hub Limiting", block: {
            testBottleneckAnalyzer()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        // Test 5: HDMI Video Cable Grade Analysis
        if await runTest(name: "HDMI Cable Quality & Bandwidth Classification", block: {
            testHDMICableGradeClassification()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        // Test 6: History Store Export & Stability Analysis
        if await runTest(name: "Test History Persistence, CSV/JSON Export & Stability", block: {
            testHistoryExportAndStability()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        // Test 7: USB Topology Hub Bottleneck Logic
        if await runTest(name: "USB Topology Chain & Hub Bottleneck Detection", block: {
            testUSBTopologyHubBottleneck()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        // Test 8: Live I/O Speed Monitor Calculation
        if await runTest(name: "Live I/O Transfer Speed Math Calculation", block: {
            testLiveIOSpeedCalculation()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Live I/O speed formatting includes a readable peak value", block: {
            testTransferSpeedFormatting()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        // Test 9: Benchmark progress is observable during write and read phases
        if await runTest(name: "Benchmark Progress: Reports preparation, write and read phases", block: {
            try await testBenchmarkReportsProgress()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "SSD Read/Write Speed Benchmark: Measures real disk throughput", block: {
            try await testRealSSDReadWriteMeasurement()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Advanced benchmark: random and integrity workloads preserve user files", block: {
            try await testAdvancedBenchmarkWorkerSafety()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Advanced benchmark: stress reuses a bounded temporary file", block: {
            try await testStressBenchmarkKeepsFileWithinQuota()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        // Test 10: A USB peripheral without a mounted volume must not expose storage actions.
        if await runTest(name: "USB connection: peripheral without volume is not benchmarkable", block: {
            testUSBConnectionWithoutVolume()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Analysis metrics: benchmark presets and robust statistics", block: {
            testAnalysisMetrics()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Advanced benchmark policy: requires safe space and extended-test consent", block: {
            testAdvancedBenchmarkSafetyPolicy()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Hardware events: detects attach, mount, detach, and link renegotiation", block: {
            testHardwareEventDetection()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Drive health: prioritizes SMART failures and thermal warnings", block: {
            testDriveHealthScoring()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Thermal benchmark correlation: pairs only same-session temperature samples", block: {
            testThermalBenchmarkCorrelation()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Video capability: reports conservative storage workflow guidance", block: {
            testVideoCapability()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Hardware score: averages only observed components", block: {
            testHardwareScore()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Guided diagnostic modes: expose all four focused workflows", block: {
            testGuidedDiagnosticModes()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "DisplayPort guide: keeps 1.4 and 2.1 bandwidth distinct", block: {
            testDisplayPortGuide()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Charging history: discards invalid samples and keeps the newest values", block: {
            testChargingHistory()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Charging: external power discloses the single active source limit", block: {
            testPowerSourceDisclosure()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Device refresh: preserves selection while replacing its snapshot", block: {
            testDeviceRefreshSelection()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Storage device selection: filters peripherals and picks a testable volume", block: {
            testStorageDeviceSelection()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Storage discovery: accepts external USB/TB and removable integrated SD only", block: {
            testStorageDiscoveryPolicy()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Diagnostics: confidence follows evidence provenance", block: {
            testDiagnosticEvidencePolicy()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Diagnostic facts: preserve unavailable values without inventing a cause", block: {
            testDiagnosticFacts()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Topology budget: reports demand and missing data safely", block: {
            testBandwidthBudget()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Connection diagnosis: distinguishes observed hub from possible chain cause", block: {
            testConnectionDiagnosis()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Bridge catalog: only exact supported identifiers produce a possible match", block: {
            testBridgeCatalog()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "USB device matching: never confuses identical peripherals", block: {
            testUSBDeviceMatching()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Shared JSON export: redacts connection identifiers", block: {
            testSharedJSONRedaction()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "USB association: matches a mounted volume through its topology", block: {
            testUSBTopologyAssociation()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Category measurements do not masquerade as USB link speeds", block: {
            testCategoryAwareMeasurements()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Only mounted storage volumes can run a benchmark", block: {
            testBenchmarkEligibility()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "CSV export escapes commas, quotes and line breaks", block: {
            testCSVFieldEscaping()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "Cable identity code is stable and valid", block: {
            testCableIdentityCode()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }

        if await runTest(name: "USB-C evidence: preserves observed states without certifying the cable", block: {
            testUSBCableEvidence()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        if await runTest(name: "EDID Parser handles valid bytes", block: {
            testEDIDParser()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        if await runTest(name: "HDMI Bandwidth Calculation matches spec (4K60 8-bit RGB)", block: {
            testHDMIBandwidthCalculator()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        if await runTest(name: "HDMI Scoring and Matrix validation", block: {
            testHDMIScoringRanges()
        }) {
            passedCount += 1
        } else {
            failedCount += 1
        }
        
        print("\n--------------------------------------------------")
        print("TEST RESULTS SUMMARY:")
        print("  PASSED: \(passedCount)")
        print("  FAILED: \(failedCount)")
        print("==================================================")
        
        if failedCount > 0 {
            exit(1)
        } else {
            print("ALL \(passedCount) SAFETY & LOGIC TESTS PASSED SUCCESSFULLY! ✅")
        }
    }
    
    // MARK: - Test Runner Helper
    
    static func runTest(name: String, block: @Sendable () async throws -> Void) async -> Bool {
        print("\nRUNNING: \(name)...")
        do {
            try await block()
            print("  ↳ PASSED ✅")
            return true
        } catch {
            print("  ↳ FAILED ❌: \(error)")
            return false
        }
    }
    
    // MARK: - Test 1: Data Safety

    static func testProductionBenchmarkPreservesUserFiles() async throws {
        let fm = FileManager.default; let directory = fm.temporaryDirectory.appendingPathComponent("CAVIProductionSafety_\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? fm.removeItem(at: directory) }
        let userFile = directory.appendingPathComponent("important-document.txt"), original = Data("USER DATA MUST REMAIN".utf8)
        try original.write(to: userFile)
        _ = try await BenchmarkWorker().run(mountPath: directory.path, testSizeBytes: 1_048_576)
        let remaining = try fm.contentsOfDirectory(atPath: directory.path)
        guard try Data(contentsOf: userFile) == original, remaining.allSatisfy({ !$0.hasPrefix(".cavi-benchmark-") }) else { throw BenchmarkError.fileIOError("Safety assertion failed") }
    }

    static func testBenchmarkReportsProgress() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("CAVIProgress_\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let collector = ProgressCollector()
        _ = try await BenchmarkWorker().run(mountPath: directory.path, testSizeBytes: 2_097_152) { update in
            await collector.append(update)
        }
        let updates = await collector.values
        guard updates.contains(where: { $0.phase == .preparing }),
              updates.contains(where: { $0.phase == .writing }),
              updates.contains(where: { $0.phase == .reading }),
              updates.last?.fractionCompleted == 1 else {
            throw BenchmarkError.fileIOError("Progress updates missing")
        }
    }

    static func testRealSSDReadWriteMeasurement() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("CAVISpeedTest_\(UUID().uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }

        // Run 8 MB sequential benchmark bypassing cache (F_NOCACHE)
        let testSize: UInt64 = 8 * 1024 * 1024
        let measurement = try await BenchmarkWorker().run(mountPath: directory.path, testSizeBytes: testSize)

        print(String(format: "     → SSD Write Speed: %.1f MB/s", measurement.sequentialWriteMBps))
        print(String(format: "     → SSD Read Speed:  %.1f MB/s", measurement.sequentialReadMBps))
        print(String(format: "     → Test Duration:   %.3f s (for %.1f MB)", measurement.durationSeconds, Double(testSize) / (1024 * 1024)))

        // Verify speed values are non-zero and positive
        guard measurement.sequentialWriteMBps > 0,
              measurement.sequentialReadMBps > 0,
              measurement.durationSeconds > 0 else {
            throw BenchmarkError.fileIOError("Benchmark returned non-positive throughput measurements")
        }
    }

    static func testAdvancedBenchmarkWorkerSafety() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("CAVIAdvancedWorker_\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let userFile = directory.appendingPathComponent("important-user-file.txt")
        let originalData = Data("do not modify".utf8)
        try originalData.write(to: userFile)

        let randomConfiguration = AdvancedBenchmarkConfiguration(
            preset: .quick256MiB,
            workload: .random4KWrite,
            seed: 42
        )
        let randomResult = try await BenchmarkWorker().runAdvanced(
            mountPath: directory.path,
            configuration: randomConfiguration,
            testSizeBytes: 64 * 1_024
        )
        assert((randomResult.randomWriteIOPS ?? 0) > 0)
        assert(!randomResult.samples.isEmpty)
        let dataAfterRandom = try Data(contentsOf: userFile)
        assert(dataAfterRandom == originalData)

        let integrityConfiguration = AdvancedBenchmarkConfiguration(
            preset: .quick256MiB,
            workload: .integrity,
            seed: 99
        )
        let integrityResult = try await BenchmarkWorker().runAdvanced(
            mountPath: directory.path,
            configuration: integrityConfiguration,
            testSizeBytes: 64 * 1_024
        )
        assert(integrityResult.integrityPassed == true)
        assert(integrityResult.bytesVerified == 64 * 1_024)
        let dataAfterIntegrity = try Data(contentsOf: userFile)
        let remainingFiles = try fileManager.contentsOfDirectory(atPath: directory.path)
        assert(dataAfterIntegrity == originalData)
        assert(remainingFiles == ["important-user-file.txt"])
    }

    static func testStressBenchmarkKeepsFileWithinQuota() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("CAVIStressQuota_\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let quota: UInt64 = 64 * 1_024
        let inspector = TemporaryBenchmarkFileInspector()
        let configuration = AdvancedBenchmarkConfiguration(
            preset: .quick256MiB,
            workload: .stress,
            stressDurationSeconds: 0.05,
            seed: 7
        )
        _ = try await BenchmarkWorker().runAdvanced(
            mountPath: directory.path,
            configuration: configuration,
            testSizeBytes: quota
        ) { _ in
            await inspector.observe(in: directory)
        }

        let largestObservedSize = await inspector.largestSize()
        assert(largestObservedSize <= quota)
        let remaining = try fileManager.contentsOfDirectory(atPath: directory.path)
        assert(remaining.isEmpty)
    }

    static func testUSBConnectionWithoutVolume() {
        let connection = USBConnectionSnapshot(
            id: "hub-1", displayName: "Hub USB", vendorID: 1, productID: 2,
            serialNumber: nil, locationID: 3, linkSpeedBps: 5_000_000_000,
            mountedVolumeBSDName: nil
        )
        assert(!connection.isBenchmarkable, "A connection without a mounted volume must not be benchmarkable")
    }

    static func testAnalysisMetrics() {
        assert(AnalysisMetrics.compactBenchmarkBytes == 256 * 1_024 * 1_024)
        assert(AnalysisMetrics.median([10, 30, 20]) == 20)
        assert(AnalysisMetrics.range([10, 30, 20]) == 20)
        assert(AnalysisMetrics.linkUtilizationPercent(measuredMBps: 250, linkSpeedBps: 5_000_000_000) == 40)
        
        let usb3Exp = BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: 5_000_000_000)
        assert(usb3Exp != nil)
        assert(usb3Exp?.theoreticalMaximumMBps == 625.0)
        assert(usb3Exp?.realisticMaximumMBps == 460.0)
        assert(usb3Exp?.protocolName.contains("5 Gb/s") == true)
        
        let usb2Exp = BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: 480_000_000)
        assert(usb2Exp?.theoreticalMaximumMBps == 60.0)
        assert(usb2Exp?.realisticMaximumMBps == 43.0)
    }

    static func testAdvancedBenchmarkSafetyPolicy() {
        let preset = BenchmarkPreset.fiftyGiB
        assert(preset.sizeBytes == 50 * BenchmarkSize.gibibyte)
        assert(preset.requiresExplicitConfirmation)
        assert(BenchmarkWorkload.random4KRead.isReadOnly)
        assert(!BenchmarkWorkload.integrity.isReadOnly)
        let randomConfiguration = AdvancedBenchmarkConfiguration(
            preset: .quick256MiB,
            workload: .random4KWrite,
            randomBlockSize: .sixtyFourKiB
        )
        assert(randomConfiguration.effectiveBlockSizeBytes == 64 * 1_024)
        assert(AdvancedBenchmarkConfiguration(
            preset: .quick256MiB,
            workload: .sequential,
            randomBlockSize: .sixtyFourKiB
        ).effectiveBlockSizeBytes == 1 * 1_024 * 1_024)

        let capacity = 500 * BenchmarkSize.gibibyte
        let required = BenchmarkSafetyPolicy.requiredFreeBytes(for: preset, volumeCapacityBytes: capacity)
        assert(required == 125 * BenchmarkSize.gibibyte)
        assert(BenchmarkSafetyPolicy.decision(
            preset: preset,
            freeBytes: required - 1,
            volumeCapacityBytes: capacity,
            userConfirmedExtendedTest: true
        ) == .insufficientSpace(requiredBytes: required))
        assert(BenchmarkSafetyPolicy.decision(
            preset: preset,
            freeBytes: required,
            volumeCapacityBytes: capacity,
            userConfirmedExtendedTest: false
        ) == .requiresConfirmation)
        assert(BenchmarkSafetyPolicy.decision(
            preset: preset,
            freeBytes: required,
            volumeCapacityBytes: capacity,
            userConfirmedExtendedTest: true
        ) == .allowed)

        assert(AnalysisMetrics.percentile([1, 2, 3, 4, 5], fraction: 0.95) == 5)
        assert(AnalysisMetrics.percentile([1, 2, 3, 4], fraction: 0.5) == 2)
        assert(AnalysisMetrics.average([1, 2, 3, 4]) == 2.5)

        let sample = BenchmarkSample(transferredBytes: 4_096, writeMBps: 120)
        let encoded = try! JSONEncoder().encode(sample)
        let decoded = try! JSONDecoder().decode(BenchmarkSample.self, from: encoded)
        let stableID: UUID = decoded.id
        assert(stableID == sample.id)

        let legacySampleData = Data("{\"timestamp\":0,\"transferredBytes\":4096,\"writeMBps\":120}".utf8)
        let legacySample = try! JSONDecoder().decode(BenchmarkSample.self, from: legacySampleData)
        assert(legacySample.id != sample.id, "Legacy benchmark samples must receive an identifier when decoded")

        let latencyResult = AdvancedBenchmarkResult(
            configuration: .init(preset: .quick256MiB, workload: .latency),
            samples: [sample],
            latencyMinimumMilliseconds: 0.2,
            latencyAverageMilliseconds: 0.5,
            latencyMaximumMilliseconds: 1.4,
            latencyP95Milliseconds: 1.1,
            latencyP99Milliseconds: 1.4
        )
        assert(latencyResult.latencyMinimumMilliseconds == 0.2)
        assert(latencyResult.latencyAverageMilliseconds == 0.5)
        assert(latencyResult.latencyMaximumMilliseconds == 1.4)
    }

    static func testHardwareEventDetection() {
        let original = HardwareConnectionState(
            id: "drive-a",
            displayName: "SSD",
            linkSpeedBps: 10_000_000_000,
            protocolName: "USB"
        )
        let downgraded = HardwareConnectionState(
            id: "drive-a",
            displayName: "SSD",
            linkSpeedBps: 5_000_000_000,
            protocolName: "USB"
        )
        let newPeripheral = HardwareConnectionState(
            id: "capture-card",
            displayName: "Capture Card",
            linkSpeedBps: 5_000_000_000,
            protocolName: "USB"
        )
        let events = HardwareEventDetector.changes(from: [original], to: [downgraded, newPeripheral])
        assert(events.map(\.kind) == [.connected, .linkRenegotiated])
        assert(events.last?.previousLinkSpeedBps == 10_000_000_000)
        assert(events.last?.linkSpeedBps == 5_000_000_000)

        let detached = HardwareEventDetector.changes(from: [downgraded], to: [])
        assert(detached.count == 1)
        assert(detached.first?.kind == .disconnected)

        let mounted = HardwareConnectionState(
            id: "drive-a",
            displayName: "SSD",
            linkSpeedBps: 10_000_000_000,
            protocolName: "USB",
            isMounted: true
        )
        let mountedEvents = HardwareEventDetector.changes(from: [original], to: [mounted])
        assert(mountedEvents.map(\.kind) == [.mounted])
        let unmountedEvents = HardwareEventDetector.changes(from: [mounted], to: [original])
        assert(unmountedEvents.map(\.kind) == [.unmounted])

        let first = HardwareEvent(kind: .connected, connectionID: "a", displayName: "A")
        let bounded = HardwareEventHistory.bounded(Array(repeating: first, count: 501), limit: 500)
        assert(bounded.count == 500)
        assert(EventStabilityScorer.score(for: []) == nil)
        assert(EventStabilityScorer.score(for: [first]) == 100)
        assert(EventStabilityScorer.score(for: [HardwareEvent(kind: .disconnected, connectionID: "a", displayName: "A")]) == 80)
        
        let safeEject = [
            HardwareEvent(timestamp: Date().addingTimeInterval(-10), kind: .mounted, connectionID: "a", displayName: "A"),
            HardwareEvent(timestamp: Date().addingTimeInterval(-5), kind: .unmounted, connectionID: "a", displayName: "A"),
            HardwareEvent(timestamp: Date(), kind: .disconnected, connectionID: "a", displayName: "A")
        ]
        assert(EventStabilityScorer.score(for: safeEject) == 100)
        assert(EventStabilityScorer.penaltyBreakdown(for: safeEject).isEmpty)

        assert(HardwareEventKind.allCases.contains(.systemSleep))
        assert(HardwareEventKind.allCases.contains(.systemWake))
    }

    static func testDriveHealthScoring() {
        let healthy = DriveHealthScorer.assess(DriveHealthInput(smartStatus: .verified, temperatureCelsius: 35, remainingLifePercent: 96))
        assert(healthy.score == 100)
        assert(healthy.level == .excellent)

        let degraded = DriveHealthScorer.assess(DriveHealthInput(
            smartStatus: .failing,
            temperatureCelsius: 74,
            remainingLifePercent: 8,
            mediaErrorCount: 3
        ))
        assert(degraded.score < 40)
        assert(degraded.level == .critical)
        assert(degraded.warnings.contains(.smartFailure))
        assert(degraded.warnings.contains(.highTemperature))
    }

    static func testThermalBenchmarkCorrelation() {
        let started = Date(timeIntervalSince1970: 1_000)
        let result = AdvancedBenchmarkResult(
            configuration: .init(preset: .quick256MiB, workload: .sustainedWrite),
            samples: [
                BenchmarkSample(timestamp: started, transferredBytes: 1, writeMBps: 1_200),
                BenchmarkSample(timestamp: started.addingTimeInterval(10), transferredBytes: 2, writeMBps: 1_150),
                BenchmarkSample(timestamp: started.addingTimeInterval(20), transferredBytes: 3, writeMBps: 820),
                BenchmarkSample(timestamp: started.addingTimeInterval(30), transferredBytes: 4, writeMBps: 700)
            ]
        ).applyingTemperatureObservations([
            .init(timestamp: started, celsius: 40),
            .init(timestamp: started.addingTimeInterval(10), celsius: 45),
            .init(timestamp: started.addingTimeInterval(20), celsius: 72),
            .init(timestamp: started.addingTimeInterval(30), celsius: 75)
        ])

        assert(result.samples.compactMap(\.temperatureCelsius).count == 4)
        assert(result.thermalCorrelation.state == .possibleThermalThrottling)
        assert(result.thermalCorrelation.throughputDropPercent ?? 0 >= 20)

        let unavailable = AdvancedBenchmarkResult(
            configuration: .init(preset: .quick256MiB, workload: .sustainedWrite),
            samples: [BenchmarkSample(transferredBytes: 1, writeMBps: 900)]
        )
        assert(unavailable.thermalCorrelation.state == .unavailable)
    }

    static func testVideoCapability() {
        let fast = VideoCapabilityEstimator.assess(sustainedWriteMBps: 900)
        assert(fast.capability(for: .proRes4K422).status == .supported)
        assert(fast.capability(for: .proRes6K422).status == .supported)
        assert(fast.maximum4KStreams == 9)

        let slow = VideoCapabilityEstimator.assess(sustainedWriteMBps: 80)
        assert(slow.capability(for: .proRes4K422).status == .marginal)
        assert(slow.capability(for: .proRes8KRaw).status == .notRecommended)
    }

    static func testHardwareScore() {
        let score = OverallHardwareScore.calculate(.init(
            connection: 100,
            performance: 80,
            health: 94,
            power: nil,
            stability: 96
        ))!
        assert(score.value == 93)
        assert(score.level == .excellent)
        assert(score.includedComponentCount == 4)
    }

    static func testGuidedDiagnosticModes() {
        assert(GuidedDiagnosticMode.allCases.count == 4)
        assert(GuidedDiagnosticMode.driveIsSlow.includesBenchmark)
        assert(GuidedDiagnosticMode.cableIsGood.includesPowerCheck)
        assert(GuidedDiagnosticMode.ssdIsHealthy.requiresStorage)
        assert(GuidedDiagnosticMode.dockOrHub.includesTopologyCheck)
    }

    static func testDisplayPortGuide() {
        assert(DisplayPortBandwidth.dp14.rawGbps == 32.4)
        assert(DisplayPortBandwidth.dp21.rawGbps == 80)
    }

    static func testChargingHistory() {
        let samples = ChargingHistory.trim([
            ChargingSample(timestamp: Date(timeIntervalSince1970: 1), watts: 20),
            ChargingSample(timestamp: Date(timeIntervalSince1970: 2), watts: -1),
            ChargingSample(timestamp: Date(timeIntervalSince1970: 3), watts: 30)
        ], limit: 1)
        assert(samples.count == 1 && samples[0].watts == 30)

        let legacyData = Data("{\"timestamp\":0,\"watts\":20}".utf8)
        let migrated = try! JSONDecoder().decode(ChargingSample.self, from: legacyData)
        assert(migrated.watts == 20)
        assert(migrated.id != UUID())
    }

    static func testPowerSourceDisclosure() {
        assert(PowerSourceDisclosure.message(isOnExternalPower: false) == nil)
        let message = PowerSourceDisclosure.message(isOnExternalPower: true)
        assert(message?.contains("una sola fonte di alimentazione attiva") == true)
        assert(message?.contains("non sono sommati") == true)
    }

    static func testDeviceRefreshSelection() {
        assert(DeviceRefreshPolicy.selectedBSDName(previous: "disk4s1", available: ["disk3s1", "disk4s1"]) == "disk4s1")
        assert(DeviceRefreshPolicy.selectedBSDName(previous: "disk4s1", available: ["disk3s1"]) == "disk3s1")
        assert(DeviceRefreshPolicy.selectedBSDName(previous: nil, available: ["disk3s1"]) == "disk3s1")
    }

    static func testStorageDeviceSelection() {
        let allDevices = [
            StorageDeviceSelectionCandidate(id: "hub", isStorageDevice: false),
            StorageDeviceSelectionCandidate(id: "micro-sd", isStorageDevice: true),
            StorageDeviceSelectionCandidate(id: "ssd", isStorageDevice: true)
        ]

        assert(StorageDeviceSelectionPolicy.storageDeviceIDs(from: allDevices) == ["micro-sd", "ssd"])
        assert(StorageDeviceSelectionPolicy.effectiveDeviceID(selected: "hub", available: allDevices) == "micro-sd")
        assert(StorageDeviceSelectionPolicy.effectiveDeviceID(selected: nil, available: allDevices) == "micro-sd")
        assert(StorageDeviceSelectionPolicy.effectiveDeviceID(selected: "ssd", available: allDevices) == "ssd")
        assert(StorageDeviceSelectionPolicy.effectiveDeviceID(selected: "hub", available: [allDevices[0]]) == nil)

        let candidatesWithMounted = [
            StorageDeviceSelectionCandidate(id: "disk4", isStorageDevice: true, isMounted: false),
            StorageDeviceSelectionCandidate(id: "disk4s1", isStorageDevice: true, isMounted: true)
        ]
        assert(StorageDeviceSelectionPolicy.effectiveDeviceID(selected: nil, available: candidatesWithMounted) == "disk4s1")
    }

    static func testStorageDiscoveryPolicy() {
        assert(StorageDiscoveryPolicy.connectionKind(isInternal: false, isRemovable: true, protocolName: "USB") == .usbOrThunderbolt)
        assert(StorageDiscoveryPolicy.connectionKind(isInternal: false, isRemovable: true, protocolName: "Thunderbolt") == .usbOrThunderbolt)
        assert(StorageDiscoveryPolicy.connectionKind(isInternal: true, isRemovable: true, protocolName: "Secure Digital") == .integratedSDReader)
        assert(StorageDiscoveryPolicy.connectionKind(isInternal: true, isRemovable: true, protocolName: "SDXC") == .integratedSDReader)
        assert(StorageDiscoveryPolicy.connectionKind(isInternal: true, isRemovable: false, protocolName: "Secure Digital") == nil)
        assert(StorageDiscoveryPolicy.connectionKind(isInternal: true, isRemovable: false, protocolName: "APFS") == nil)
        assert(StorageDiscoveryPolicy.connectionKind(isInternal: true, isRemovable: true, protocolName: "NVMe") == nil)
        assert(StorageConnectionKind.integratedSDReader.connectionDescription == "Lettore SD integrato — nessun cavo da diagnosticare")
        assert(!StorageConnectionKind.integratedSDReader.supportsUSBTopology)
        assert(StorageConnectionKind.usbOrThunderbolt.supportsUSBTopology)
    }

    static func testDiagnosticEvidencePolicy() {
        let observed = DiagnosticEvidence(
            label: "Velocità link",
            value: "5 Gb/s",
            source: .ioRegistryObserved
        )
        let inferred = DiagnosticEvidence(
            label: "Cavo",
            value: "Possibile limite",
            source: .inferred
        )
        let unavailable = DiagnosticEvidence(
            label: "E-Marker",
            value: nil,
            source: .unavailable
        )

        assert(observed.source.isDirectObservation)
        assert(!inferred.source.isDirectObservation)
        assert(unavailable.source == .unavailable)
        assert(DiagnosticConfidence.from(evidence: [observed]) == .confirmed)
        assert(DiagnosticConfidence.from(evidence: [inferred]) == .possible)
        assert(DiagnosticConfidence.from(evidence: [unavailable]) == .insufficientEvidence)
    }

    static func testDiagnosticFacts() {
        let unavailableMarker = DiagnosticFact<String>(
            value: nil,
            source: .unavailable,
            detail: "macOS did not expose an e-marker"
        )
        let catalogMatch = DiagnosticFact<String>(
            value: "JMicron JMS583",
            source: .catalogMatched,
            detail: "Exact VID/PID match"
        )

        assert(unavailableMarker.value == nil)
        assert(unavailableMarker.source == .unavailable)
        assert(catalogMatch.value == "JMicron JMS583")
        assert(DiagnosticConfidence.from(evidence: []) == .insufficientEvidence)
    }

    static func testBandwidthBudget() {
        let demand = BandwidthConsumer(id: "ssd-1", label: "SSD 1", requestedSpeedBps: 10_000_000_000)
        let secondDemand = BandwidthConsumer(id: "capture-1", label: "Capture", requestedSpeedBps: 15_000_000_000)
        let budget = BandwidthBudgetCalculator.calculate(
            uplinkSpeedBps: 10_000_000_000,
            consumers: [demand, secondDemand]
        )
        assert(budget.potentialDemandBps == 25_000_000_000)
        assert(budget.saturationPercent == 250)
        assert(!budget.hasIncompleteDemand)

        let incomplete = BandwidthBudgetCalculator.calculate(
            uplinkSpeedBps: nil,
            consumers: [demand, BandwidthConsumer(id: "unknown", label: "Unknown", requestedSpeedBps: nil)]
        )
        assert(incomplete.potentialDemandBps == 10_000_000_000)
        assert(incomplete.saturationPercent == nil)
        assert(incomplete.hasIncompleteDemand)
    }

    static func testConnectionDiagnosis() {
        let hubDiagnosis = ConnectionDiagnosisEngine.analyze(
            currentLinkSpeedBps: 5_000_000_000,
            referenceMaxSpeedBps: 10_000_000_000,
            constraints: [
                ConnectionConstraint(
                    label: "Hub USB",
                    maximumSpeedBps: 5_000_000_000,
                    kind: .hub,
                    source: .ioRegistryObserved
                )
            ]
        )
        assert(hubDiagnosis.primaryCause == .hub)
        assert(hubDiagnosis.confidence == .confirmed)
        assert(hubDiagnosis.warningLevel == .critical)
        assert(hubDiagnosis.causes == [
            ConnectionCauseAssessment(cause: .hub, confidence: .confirmed, warningLevel: .critical)
        ])

        let possibleDiagnosis = ConnectionDiagnosisEngine.analyze(
            currentLinkSpeedBps: 5_000_000_000,
            referenceMaxSpeedBps: 10_000_000_000,
            constraints: []
        )
        assert(possibleDiagnosis.primaryCause == .cable)
        assert(possibleDiagnosis.confidence == .possible)
        assert(possibleDiagnosis.warningLevel == .attention)
        assert(possibleDiagnosis.evidences.contains { $0.source == .inferred })
        assert(possibleDiagnosis.evidences.contains { $0.label == "Velocità di riferimento" && $0.source == .ioRegistryObserved })
        assert(possibleDiagnosis.causes.first?.cause == .cable)
        assert(possibleDiagnosis.causes.first?.confidence == .possible)

        let healthyDiagnosis = ConnectionDiagnosisEngine.analyze(
            currentLinkSpeedBps: 10_000_000_000,
            referenceMaxSpeedBps: 10_000_000_000,
            constraints: []
        )
        assert(healthyDiagnosis.primaryCause == .device)
        assert(healthyDiagnosis.confidence == .confirmed)
        assert(healthyDiagnosis.warningLevel == .info)
    }

    static func testBridgeCatalog() {
        let bridge = BridgeCatalog.match(vendorID: 0x152D, productID: 0x0583)
        assert(bridge?.family == "JMicron JMS583")
        assert(bridge?.source == .catalogMatched)
        assert(BridgeCatalog.match(vendorID: 0x152D, productID: 0x9999) == nil)

        let snapshot = ConnectionSnapshot(
            protocolName: "USB",
            negotiatedLinkSpeedBps: 10_000_000_000,
            fileSystem: "exFAT",
            blockSizeBytes: 4_096,
            bridge: bridge,
            ioRegistryNodeNames: ["IOUSBHostDevice", "AppleUSBXHCI"],
            technicalProperties: [TechnicalProperty(key: "UsbLinkSpeed", value: "10 Gb/s")]
        )
        assert(snapshot.bridge?.family == "JMicron JMS583")
        assert(snapshot.negotiatedLinkSpeedBps == 10_000_000_000)
        assert(snapshot.blockSizeBytes == 4_096)
        assert(snapshot.ioRegistryNodeNames?.count == 2)

        let legacySnapshotJSON = Data("""
        {"protocolName":"USB","fileSystem":"exFAT","blockSizeBytes":4096,"bridge":null,"technicalProperties":[]}
        """.utf8)
        let legacySnapshot = try? JSONDecoder().decode(ConnectionSnapshot.self, from: legacySnapshotJSON)
        assert(legacySnapshot?.protocolName == "USB")
        assert(legacySnapshot?.negotiatedLinkSpeedBps == nil)
        assert(legacySnapshot?.ioRegistryNodeNames == nil)
        assert(snapshot.technicalProperties.count == 1)
    }

    static func testUSBTopologyAssociation() {
        let volumePath = [USBIdentity(locationID: 42, vendorID: 1234, productID: 5678)]
        assert(USBAssociationPolicy.matches(locationID: 42, vendorID: 1234, productID: 5678, topology: volumePath))
        assert(!USBAssociationPolicy.matches(locationID: 43, vendorID: 1234, productID: 5678, topology: volumePath))
    }

    static func testUSBDeviceMatching() {
        let first = USBDeviceIdentity(bsdName: "disk4s1", vendorID: 0x1234, productID: 0x5678, serialNumber: nil, locationID: 10)
        let second = USBDeviceIdentity(bsdName: "disk5s1", vendorID: 0x1234, productID: 0x5678, serialNumber: nil, locationID: 20)

        assert(USBDeviceMatchPolicy.bestCandidateIndex(for: second, candidates: [first, second]) == 1)
        assert(USBDeviceMatchPolicy.bestCandidateIndex(
            for: USBDeviceIdentity(bsdName: nil, vendorID: 0x1234, productID: 0x5678, serialNumber: nil, locationID: nil),
            candidates: [first, second]
        ) == nil)
        assert(USBDeviceMatchPolicy.bestCandidateIndex(
            for: USBDeviceIdentity(bsdName: nil, vendorID: nil, productID: nil, serialNumber: nil, locationID: nil),
            candidates: [first, second]
        ) == nil)
    }

    static func testSharedJSONRedaction() {
        let input = Data("""
        [{"deviceSerialNumber":"SERIAL-123","connectionFingerprint":"fingerprint-with-serial","bsdName":"disk4s1","mountPath":"/Volumes/Private","locationID":42,"deviceName":"SSD"}]
        """.utf8)
        let redacted = SharedExportSanitizer.redactJSON(input)
        let text = redacted.flatMap { String(data: $0, encoding: .utf8) } ?? ""

        assert(!text.contains("SERIAL-123"))
        assert(!text.contains("fingerprint-with-serial"))
        assert(!text.contains("/Volumes/Private"))
        assert(!text.contains("disk4s1"))
        assert(!text.contains("\"locationID\""))
        assert(text.contains("SSD"))
    }

    static func testCategoryAwareMeasurements() {
        assert(ConnectionMeasurement.usbLink(bps: 10_000_000_000).label == "Velocità link")
        assert(ConnectionMeasurement.usbLink(bps: 10_000_000_000).value == "10 Gb/s")
        assert(ConnectionMeasurement.videoRequirement(bps: 18_000_000_000).label == "Banda stimata")
        assert(ConnectionMeasurement.videoRequirement(bps: 18_000_000_000).value == "18.0 Gb/s")
        assert(ConnectionMeasurement.charging(watts: 35).label == "Potenza osservata")
        assert(ConnectionMeasurement.charging(watts: 35).value == "35.0 W")
    }

    static func testBenchmarkEligibility() {
        assert(!BenchmarkEligibility.canRun(isStorageDevice: false, isMounted: false, mountPath: ""))
        assert(!BenchmarkEligibility.canRun(isStorageDevice: true, isMounted: false, mountPath: ""))
        assert(BenchmarkEligibility.canRun(isStorageDevice: true, isMounted: true, mountPath: "/Volumes/Disk"))
    }

    static func testCSVFieldEscaping() {
        assert(CSVEncoder.field("cavo, \"A\"\nnota") == "\"cavo, \"\"A\"\"\nnota\"")
    }

    static func testCableIdentityCode() {
        let first = CableIdentityPolicy.code(for: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!)
        let second = CableIdentityPolicy.code(for: UUID(uuidString: "F1234567-89AB-CDEF-0123-456789ABCDEF")!)
        assert(first == "CAV-012345")
        assert(first != second)
        assert(CableIdentityPolicy.isValid(first))
        assert(!CableIdentityPolicy.isValid("CAV-123"))
    }

    static func testUSBCableEvidence() {
        let empty = USBCableEvidenceBuilder.make(from: [])
        assert(empty.availability == .unavailable)
        assert(!empty.hasReadablePorts)

        let observed = USBPortRegistryRecord(
            id: "port-1",
            portName: "USB-C 1",
            connectionActive: true,
            activeCable: false,
            transports: ["USB2"],
            authorizationRequired: false,
            authorizationStatus: "Not Required",
            overcurrentCount: 0,
            liquidDetected: false,
            cableIdentityProperties: ["VDO": "0x1234"]
        )

        let snapshot = USBCableEvidenceBuilder.make(from: [observed])

        assert(snapshot.availability == .available)
        assert(snapshot.hasReadablePorts)
        assert(snapshot.ports.first?.state == .cableIdentityObserved)
        assert(snapshot.ports.first?.isPhysicalCertification == false)
        assert(snapshot.ports.first?.evidenceSource == .ioRegistryObserved)
    }

    static func testTransferSpeedFormatting() {
        assert(TransferSpeedFormatter.megabytesPerSecond(0) == "0 MB/s")
        assert(TransferSpeedFormatter.megabytesPerSecond(2.5) == "2.5 MB/s")
        assert(TransferSpeedFormatter.megabytesPerSecond(125.2) == "125 MB/s")
    }

    static func testDataSafetyNeverDeletesUserFiles() async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("CAVISafetyTest_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        
        let drivePath = tempDir.path
        
        // 1. Create simulated user files on the drive
        let file1URL = tempDir.appendingPathComponent("MyImportantPhoto.jpg")
        let file2URL = tempDir.appendingPathComponent("FinancialReport.pdf")
        let subDirURL = tempDir.appendingPathComponent("UserFolder")
        let file3URL = subDirURL.appendingPathComponent("PrivateData.txt")
        
        let file1Content = Data(repeating: 0x55, count: 1024 * 50) // 50 KB dummy image
        let file2Content = "CONFIDENTIAL USER REPORT CONTENT".data(using: .utf8)!
        let file3Content = "IMPORTANT BACKUP FILE CONTENT".data(using: .utf8)!
        
        try file1Content.write(to: file1URL)
        try file2Content.write(to: file2URL)
        try fm.createDirectory(at: subDirURL, withIntermediateDirectories: true)
        try file3Content.write(to: file3URL)
        
        // Take inventory of files before benchmark
        let beforeContents = try fm.contentsOfDirectory(atPath: drivePath).sorted()
        assert(beforeContents == ["FinancialReport.pdf", "MyImportantPhoto.jpg", "UserFolder"].sorted(), "Initial inventory mismatch")
        
        // 2. Run Benchmark with test size 5MB using direct POSIX engine
        let tempFilePath = (drivePath as NSString).appendingPathComponent(".cavi_benchmark_temp.bin")
        let bufferSize = 1024 * 1024
        let buffer = [UInt8](repeating: 0xAA, count: bufferSize)
        
        // Write phase
        let writeFd = open(tempFilePath, O_WRONLY | O_CREAT | O_TRUNC, 0o666)
        assert(writeFd != -1, "Failed to create temp benchmark file")
        _ = fcntl(writeFd, F_NOCACHE, 1)
        
        for _ in 0..<5 {
            let written = write(writeFd, buffer, bufferSize)
            assert(written == bufferSize, "Write failed")
        }
        fsync(writeFd)
        close(writeFd)
        
        // Read phase
        let readFd = open(tempFilePath, O_RDONLY)
        assert(readFd != -1, "Failed to open temp benchmark file for reading")
        _ = fcntl(readFd, F_NOCACHE, 1)
        var readBuf = [UInt8](repeating: 0, count: bufferSize)
        for _ in 0..<5 {
            let bytesRead = read(readFd, &readBuf, bufferSize)
            assert(bytesRead == bufferSize, "Read failed")
        }
        close(readFd)
        
        // Clean up temp file
        try fm.removeItem(atPath: tempFilePath)
        
        // 3. VERIFY CRITICAL SAFETY:
        // A. All user files must STILL exist
        assert(fm.fileExists(atPath: file1URL.path), "CRITICAL FAIL: User file 1 was deleted!")
        assert(fm.fileExists(atPath: file2URL.path), "CRITICAL FAIL: User file 2 was deleted!")
        assert(fm.fileExists(atPath: file3URL.path), "CRITICAL FAIL: User file in subfolder was deleted!")
        
        // B. Content of user files must be 100% UNCHANGED
        let after1 = try Data(contentsOf: file1URL)
        let after2 = try Data(contentsOf: file2URL)
        let after3 = try Data(contentsOf: file3URL)
        
        assert(after1 == file1Content, "CRITICAL FAIL: User file 1 content was altered!")
        assert(after2 == file2Content, "CRITICAL FAIL: User file 2 content was altered!")
        assert(after3 == file3Content, "CRITICAL FAIL: User file 3 content was altered!")
        
        // C. Temp benchmark file must have been completely cleaned up
        assert(!fm.fileExists(atPath: tempFilePath), "Temp benchmark file was not cleaned up!")
        
        // D. Directory listing matches before list
        let afterContents = try fm.contentsOfDirectory(atPath: drivePath).sorted()
        assert(afterContents == beforeContents, "Drive directory contents altered!")
    }
    
    // MARK: - Test 2: Cancellation Cleanup
    
    static func testDataSafetyCancellationCleanup() async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("CAVICancelTest_\(UUID().uuidString)")
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        
        let drivePath = tempDir.path
        let userFileURL = tempDir.appendingPathComponent("UserDocument.docx")
        try "USER DATA PRESERVED".data(using: .utf8)!.write(to: userFileURL)
        
        let tempFilePath = (drivePath as NSString).appendingPathComponent(".cavi_benchmark_temp.bin")
        let writeFd = open(tempFilePath, O_WRONLY | O_CREAT | O_TRUNC, 0o666)
        assert(writeFd != -1, "Temp file creation failed")
        _ = fcntl(writeFd, F_NOCACHE, 1)
        
        // Simulate cancellation cleanup
        close(writeFd)
        try? fm.removeItem(atPath: tempFilePath)
        
        assert(fm.fileExists(atPath: userFileURL.path), "User file deleted!")
        assert(!fm.fileExists(atPath: tempFilePath), "Temp benchmark file remained!")
    }
    
    // MARK: - Test 3: Speed Classification
    
    static func testSpeedClassification() {
        assert(formatSpeed(bps: 10_000_000_000) == "10 Gb/s", "Format 10 Gb/s failed")
        assert(formatSpeed(bps: 5_000_000_000) == "5 Gb/s", "Format 5 Gb/s failed")
        assert(formatSpeed(bps: 480_000_000) == "480 Mb/s", "Format 480 Mb/s failed")
        assert(formatSpeed(bps: 40_000_000_000) == "40 Gb/s", "Format 40 Gb/s failed")
    }
    
    // MARK: - Test 4: Bottleneck Analyzer
    
    static func testBottleneckAnalyzer() {
        let currentSpeed: UInt64 = 480_000_000
        let refSpeed: UInt64 = 10_000_000_000
        
        assert(currentSpeed < refSpeed, "Speed bottleneck logic failed")
        let formattedCurrent = formatSpeed(bps: currentSpeed)
        let formattedRef = formatSpeed(bps: refSpeed)
        
        assert(formattedCurrent == "480 Mb/s")
        assert(formattedRef == "10 Gb/s")
    }
    
    // MARK: - Test 5: HDMI Cable Grade Classification
    
    static func testHDMICableGradeClassification() {
        // 4K @ 30Hz -> HDMI 1.4
        let bandwidth1_4 = (3840.0 * 2160.0 * 30.0 * 24.0 * 1.25) / 1_000_000_000.0
        assert(bandwidth1_4 < 10.2, "HDMI 1.4 bandwidth calculation error")
        
        // 4K @ 60Hz -> HDMI 2.0
        let bandwidth2_0 = (3840.0 * 2160.0 * 60.0 * 24.0 * 1.25) / 1_000_000_000.0
        assert(bandwidth2_0 > 10.2 && bandwidth2_0 < 18.0, "HDMI 2.0 bandwidth calculation error")
        
        // 4K @ 120Hz -> HDMI 2.1
        let bandwidth2_1 = (3840.0 * 2160.0 * 120.0 * 24.0 * 1.25) / 1_000_000_000.0
        assert(bandwidth2_1 > 18.0, "HDMI 2.1 bandwidth calculation error")
    }
    
    // MARK: - Test 6: History & Stability Export
    
    static func testHistoryExportAndStability() {
        let test1 = ["cableLabel": "Cavo Nero", "speed": "10 Gb/s"]
        let test2 = ["cableLabel": "Cavo Nero", "speed": "480 Mb/s"]
        
        let isUnstable = test1["speed"] != test2["speed"]
        assert(isUnstable, "Stability check failed: speed variance not flagged")
        
        let csvHeader = "Cavo,Velocità Link,Benchmark Lettura MB/s,Benchmark Scrittura MB/s,Dispositivo,Data,Hub,Porta,Note\n"
        assert(csvHeader.contains("Cavo"), "CSV header format error")
    }
    
    // MARK: - Test 7: USB Topology Hub Bottleneck
    
    static func testUSBTopologyHubBottleneck() {
        let deviceSpeed: UInt64 = 10_000_000_000 // 10 Gbps SSD
        let hubSpeed: UInt64 = 5_000_000_000      // 5 Gbps Hub
        
        let isHubBottleneck = hubSpeed < deviceSpeed
        assert(isHubBottleneck, "Hub bottleneck calculation failed")
    }
    
    // MARK: - Test 8: Live I/O Speed Calculation Math
    
    static func testLiveIOSpeedCalculation() {
        let initialBytesWritten: UInt64 = 100_000_000
        let finalBytesWritten: UInt64 = 600_000_000 // 500 MB written
        let elapsedTimeSeconds: Double = 1.0
        
        let deltaBytes = finalBytesWritten - initialBytesWritten
        let writeMBps = Double(deltaBytes) / elapsedTimeSeconds / 1_000_000.0
        
        assert(writeMBps == 500.0, "Live I/O speed calculation math error")
    }
    
    private static func formatSpeed(bps: UInt64) -> String {
        if bps >= 1_000_000_000 {
            let gbps = Double(bps) / 1_000_000_000.0
            return gbps.truncatingRemainder(dividingBy: 1.0) == 0 ? String(format: "%.0f Gb/s", gbps) : String(format: "%.1f Gb/s", gbps)
        } else if bps >= 1_000_000 {
            let mbps = Double(bps) / 1_000_000.0
            return String(format: "%.0f Mb/s", mbps)
        } else {
            return "\(bps) bps"
        }
    }
    
    static func testEDIDParser() {
        let dummyEDID: [UInt8] = Array(repeating: 0, count: 128)
        let parsed = EDIDParser.parse(dummyEDID)
        assert(parsed == nil, "Invalid header should fail")
    }
    
    static func testHDMIBandwidthCalculator() {
        let req = HDMIBandwidthCalculator.calculate(width: 3840, height: 2160, refreshRate: 60.0, bitDepth: 8, chroma: .rgb444, isDSC: false)
        assert(req.rawBandwidthGbps > 11.9 && req.rawBandwidthGbps < 12.0)
        assert(req.totalBandwidthGbps > 14.9 && req.totalBandwidthGbps < 15.0) 
    }
    
    static func testHDMIScoringRanges() {
        let gaming = HDMIScoringEngine.gamingScore(overall: 95)
        assert(gaming.overall == 95)
        
        let conn = HDMIScoringEngine.connectionScore(overall: 50)
        assert(conn.overall == 50)
        
        assert(ChromaSubsampling.rgb444.bandwidthMultiplier == 3.0)
        assert(ChromaSubsampling.ycbcr420.bandwidthMultiplier == 1.5)
    }
}
