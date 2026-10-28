import XCTest
@testable import CAVICore

final class AnalysisAndPolicyTests: XCTestCase {
    // MARK: Statistics

    func testMedianRangeAverageAndPercentile() {
        XCTAssertNil(AnalysisMetrics.median([]))
        XCTAssertEqual(AnalysisMetrics.median([3, 1, 2]), 2)
        XCTAssertEqual(AnalysisMetrics.median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(AnalysisMetrics.range([5, 1, 9]), 8)
        XCTAssertNil(AnalysisMetrics.range([]))
        XCTAssertEqual(AnalysisMetrics.average([2, 4, 9]), 5)
        XCTAssertNil(AnalysisMetrics.average([]))

        let values = (1...100).map(Double.init)
        XCTAssertEqual(AnalysisMetrics.percentile(values, fraction: 0.95), 95)
        XCTAssertEqual(AnalysisMetrics.percentile(values, fraction: 0), 1)
        XCTAssertEqual(AnalysisMetrics.percentile(values, fraction: 1), 100)
        XCTAssertNil(AnalysisMetrics.percentile(values, fraction: 1.5))
        XCTAssertNil(AnalysisMetrics.percentile([], fraction: 0.5))
    }

    func testLinkUtilization() {
        XCTAssertEqual(AnalysisMetrics.linkUtilizationPercent(measuredMBps: 500, linkSpeedBps: 5_000_000_000), 80)
        XCTAssertNil(AnalysisMetrics.linkUtilizationPercent(measuredMBps: 500, linkSpeedBps: nil))
        XCTAssertNil(AnalysisMetrics.linkUtilizationPercent(measuredMBps: 500, linkSpeedBps: 0))
        XCTAssertNil(AnalysisMetrics.linkUtilizationPercent(measuredMBps: -1, linkSpeedBps: 5_000_000_000))
    }

    // MARK: Formatting and identity

    func testTransferSpeedFormatting() {
        XCTAssertEqual(TransferSpeedFormatter.linkSpeed(480_000_000), "480 Mb/s")
        XCTAssertEqual(TransferSpeedFormatter.linkSpeed(5_000_000_000), "5 Gb/s")
        XCTAssertEqual(TransferSpeedFormatter.linkSpeed(1_500_000_000), "1.5 Gb/s")
        XCTAssertEqual(TransferSpeedFormatter.megabytesPerSecond(0.05), "0 MB/s")
        XCTAssertEqual(TransferSpeedFormatter.megabytesPerSecond(.nan), "0 MB/s")
        XCTAssertEqual(TransferSpeedFormatter.megabytesPerSecond(.infinity), "0 MB/s")
        XCTAssertEqual(TransferSpeedFormatter.megabytesPerSecond(4.25), "4.2 MB/s")
        XCTAssertEqual(TransferSpeedFormatter.megabytesPerSecond(987.6), "988 MB/s")
    }

    func testCableIdentityCodes() throws {
        let id = try XCTUnwrap(UUID(uuidString: "ab12cd34-0000-0000-0000-000000000000"))
        let code = CableIdentityPolicy.code(for: id)
        XCTAssertEqual(code, "CAV-AB12CD")
        XCTAssertTrue(CableIdentityPolicy.isValid(code))
        XCTAssertFalse(CableIdentityPolicy.isValid("CAV-ab12cd"))
        XCTAssertFalse(CableIdentityPolicy.isValid("CAV-AB12CD7"))
        XCTAssertFalse(CableIdentityPolicy.isValid("XCAV-AB12CD"))
    }

    // MARK: Benchmark presets and safety

    func testPresetSizesAndConfirmation() {
        XCTAssertEqual(BenchmarkPreset.quick256MiB.sizeBytes, 268_435_456)
        XCTAssertEqual(BenchmarkPreset.hundredGiB.sizeBytes, 100 * 1_073_741_824)
        XCTAssertEqual(BenchmarkPreset.allCases.filter(\.requiresExplicitConfirmation), [.fiftyGiB, .hundredGiB])
    }

    func testSafetyPolicyDecisions() {
        let gib = BenchmarkSize.gibibyte
        XCTAssertEqual(BenchmarkSafetyPolicy.requiredFreeBytes(for: .standard1GiB, volumeCapacityBytes: 1_000 * gib), 2 * gib)
        // 15 % of 1 TiB beats the 20 GiB floor.
        XCTAssertEqual(BenchmarkSafetyPolicy.requiredFreeBytes(for: .fiftyGiB, volumeCapacityBytes: 1_000 * gib), 50 * gib + 1_000 * gib / 100 * 15)
        XCTAssertEqual(BenchmarkSafetyPolicy.requiredFreeBytes(for: .fiftyGiB, volumeCapacityBytes: 100 * gib), 70 * gib)

        XCTAssertEqual(BenchmarkSafetyPolicy.decision(preset: .standard1GiB, freeBytes: 2 * gib, volumeCapacityBytes: 100 * gib, userConfirmedExtendedTest: false), .allowed)
        XCTAssertEqual(BenchmarkSafetyPolicy.decision(preset: .standard1GiB, freeBytes: gib, volumeCapacityBytes: 100 * gib, userConfirmedExtendedTest: false), .insufficientSpace(requiredBytes: 2 * gib))
        XCTAssertEqual(BenchmarkSafetyPolicy.decision(preset: .fiftyGiB, freeBytes: 500 * gib, volumeCapacityBytes: 100 * gib, userConfirmedExtendedTest: false), .requiresConfirmation)
        XCTAssertEqual(BenchmarkSafetyPolicy.decision(preset: .fiftyGiB, freeBytes: 500 * gib, volumeCapacityBytes: 100 * gib, userConfirmedExtendedTest: true), .allowed)
    }

    func testBlockSizeSelection() {
        XCTAssertEqual(AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: .random4KRead, randomBlockSize: .sixtyFourKiB).effectiveBlockSizeBytes, 65_536)
        XCTAssertEqual(AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: .sequential, randomBlockSize: .sixtyFourKiB).effectiveBlockSizeBytes, 1_048_576)
        XCTAssertEqual(AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: .latency, randomBlockSize: .sixtyFourKiB).effectiveBlockSizeBytes, 4_096)
        XCTAssertTrue(BenchmarkWorkload.random4KRead.isReadOnly)
        XCTAssertFalse(BenchmarkWorkload.random4KWrite.isReadOnly)
    }

    func testLegacyAdvancedConfigurationDecodesWithDefaults() throws {
        let json = #"{"preset":"standard1GiB","workload":"random4KWrite"}"#
        let configuration = try JSONDecoder().decode(AdvancedBenchmarkConfiguration.self, from: Data(json.utf8))
        XCTAssertEqual(configuration.randomBlockSize, .fourKiB)
        XCTAssertEqual(configuration.seed, 0xCA71_2026)
        XCTAssertNil(configuration.stressDurationSeconds)
    }

    func testLegacySampleWithoutIDDecodes() throws {
        let json = #"{"timestamp":0,"transferredBytes":10,"writeMBps":12.5}"#
        let sample = try JSONDecoder().decode(BenchmarkSample.self, from: Data(json.utf8))
        XCTAssertEqual(sample.transferredBytes, 10)
        XCTAssertEqual(sample.writeMBps, 12.5)
        XCTAssertNil(sample.temperatureCelsius)
    }

    // MARK: Thermal correlation

    private func samples(_ pairs: [(Double, Double)], start: Date = Date(timeIntervalSince1970: 0)) -> [BenchmarkSample] {
        pairs.enumerated().map { index, pair in
            BenchmarkSample(timestamp: start.addingTimeInterval(TimeInterval(index)), transferredBytes: UInt64(index), writeMBps: pair.1, temperatureCelsius: pair.0)
        }
    }

    func testThermalThrottlingNeedsHeatAndADrop() {
        let throttled = ThermalPerformanceCorrelation.assess(samples: samples([(40, 1000), (45, 1000), (72, 600), (75, 600)]))
        XCTAssertEqual(throttled.state, .possibleThermalThrottling)
        XCTAssertEqual(throttled.peakTemperatureCelsius, 75)
        XCTAssertEqual(try XCTUnwrap(throttled.throughputDropPercent), 40, accuracy: 0.001)

        let coolDrop = ThermalPerformanceCorrelation.assess(samples: samples([(40, 1000), (41, 1000), (50, 500), (52, 500)]))
        XCTAssertEqual(coolDrop.state, .notDetected, "A drop below 70 °C is not called throttling")

        XCTAssertEqual(ThermalPerformanceCorrelation.assess(samples: samples([(40, 1000), (80, 100), (80, 100)])).state, .unavailable)
        XCTAssertEqual(ThermalPerformanceCorrelation.assess(samples: samples([(60, 1), (60, 1), (60, 1), (60, 1)])).state, .unavailable)
    }

    func testTemperatureObservationsAttachOnlyWhenClose() {
        let start = Date(timeIntervalSince1970: 0)
        let result = AdvancedBenchmarkResult(
            configuration: AdvancedBenchmarkConfiguration(preset: .quick256MiB, workload: .sustainedWrite),
            samples: [
                BenchmarkSample(timestamp: start, transferredBytes: 1),
                BenchmarkSample(timestamp: start.addingTimeInterval(100), transferredBytes: 2)
            ]
        )
        let enriched = result.applyingTemperatureObservations([
            BenchmarkTemperatureObservation(timestamp: start.addingTimeInterval(2), celsius: 55),
            BenchmarkTemperatureObservation(timestamp: start.addingTimeInterval(90), celsius: .nan)
        ])
        XCTAssertEqual(enriched.samples.map(\.temperatureCelsius), [55, nil])
        XCTAssertEqual(enriched.samples.map(\.id), result.samples.map(\.id))
    }

    // MARK: Video workflows

    func testVideoCapabilityThresholds() {
        let assessment = VideoCapabilityEstimator.assess(sustainedWriteMBps: 200)
        XCTAssertEqual(assessment.capability(for: .proRes4K422).status, .supported)
        XCTAssertEqual(assessment.capability(for: .proRes6K422).status, .marginal)
        XCTAssertEqual(assessment.capability(for: .proRes8KRaw).status, .notRecommended)
        XCTAssertEqual(assessment.maximum4KStreams, 2)
    }

    func testVideoCapabilityIgnoresInvalidMeasurements() {
        for value in [-.infinity, .infinity, .nan, -50] as [Double] {
            let assessment = VideoCapabilityEstimator.assess(sustainedWriteMBps: value)
            XCTAssertEqual(assessment.measuredWriteMBps, 0)
            XCTAssertEqual(assessment.maximum4KStreams, 0)
        }
    }

    // MARK: Scores and history helpers

    func testOverallHardwareScoreUsesOnlyObservedComponents() {
        XCTAssertNil(OverallHardwareScore.calculate(HardwareScoreComponents(connection: nil, performance: nil, health: nil, power: nil, stability: nil)))
        let result = OverallHardwareScore.calculate(HardwareScoreComponents(connection: 100, performance: 150, health: -20, power: nil, stability: nil))
        XCTAssertEqual(result?.value, 67)
        XCTAssertEqual(result?.includedComponentCount, 3)
        XCTAssertEqual(result?.level, .attention)
        XCTAssertEqual(OverallHardwareScore.calculate(HardwareScoreComponents(connection: 90, performance: nil, health: nil, power: nil, stability: nil))?.level, .excellent)
    }

    func testChargingHistoryDropsInvalidAndOldSamples() {
        let now = Date(timeIntervalSince1970: 1_000)
        let samples = [
            ChargingSample(timestamp: now.addingTimeInterval(-120), watts: 30),
            ChargingSample(timestamp: now.addingTimeInterval(-30), watts: -1),
            ChargingSample(timestamp: now.addingTimeInterval(-20), watts: .infinity),
            ChargingSample(timestamp: now.addingTimeInterval(-10), watts: 45),
            ChargingSample(timestamp: now, watts: 60)
        ]
        XCTAssertEqual(ChargingHistory.recent(samples, limit: 10, window: 60, now: now).map(\.watts), [45, 60])
        XCTAssertEqual(ChargingHistory.trim(samples, limit: 1).map(\.watts), [60])
        XCTAssertEqual(ChargingHistory.trim(samples, limit: 0), [])
    }

    func testSelectionPolicies() {
        XCTAssertEqual(DeviceRefreshPolicy.selectedBSDName(previous: "disk4", available: ["disk3", "disk4"]), "disk4")
        XCTAssertEqual(DeviceRefreshPolicy.selectedBSDName(previous: "disk9", available: ["disk3"]), "disk3")
        XCTAssertNil(DeviceRefreshPolicy.selectedBSDName(previous: "disk9", available: ["disk3", "disk4"]))

        let devices = [
            StorageDeviceSelectionCandidate(id: "keyboard", isStorageDevice: false, isMounted: true),
            StorageDeviceSelectionCandidate(id: "raw", isStorageDevice: true),
            StorageDeviceSelectionCandidate(id: "ssd", isStorageDevice: true, isMounted: true)
        ]
        XCTAssertEqual(StorageDeviceSelectionPolicy.effectiveDeviceID(selected: "keyboard", available: devices), "ssd")
        XCTAssertEqual(StorageDeviceSelectionPolicy.effectiveDeviceID(selected: "raw", available: devices), "raw")
        XCTAssertNil(StorageDeviceSelectionPolicy.effectiveDeviceID(selected: nil, available: []))
    }

    // MARK: Connection diagnosis

    func testBandwidthBudget() {
        let budget = BandwidthBudgetCalculator.calculate(uplinkSpeedBps: 10_000_000_000, consumers: [
            BandwidthConsumer(id: "a", label: "A", requestedSpeedBps: 5_000_000_000),
            BandwidthConsumer(id: "b", label: "B", requestedSpeedBps: 10_000_000_000),
            BandwidthConsumer(id: "c", label: "C", requestedSpeedBps: nil)
        ])
        XCTAssertEqual(budget.potentialDemandBps, 15_000_000_000)
        XCTAssertEqual(budget.saturationPercent, 150)
        XCTAssertTrue(budget.hasIncompleteDemand)

        let empty = BandwidthBudgetCalculator.calculate(uplinkSpeedBps: 0, consumers: [])
        XCTAssertNil(empty.potentialDemandBps)
        XCTAssertNil(empty.saturationPercent)
        XCTAssertFalse(empty.hasIncompleteDemand)
    }

    func testDiagnosisNeverConfirmsTheCableFromSpeedAlone() {
        let slow = ConnectionDiagnosisEngine.analyze(currentLinkSpeedBps: 480_000_000, referenceMaxSpeedBps: 10_000_000_000, constraints: [])
        XCTAssertEqual(slow.primaryCause, .cable)
        XCTAssertEqual(slow.confidence, .possible)

        let hub = ConnectionDiagnosisEngine.analyze(
            currentLinkSpeedBps: 480_000_000,
            referenceMaxSpeedBps: 10_000_000_000,
            constraints: [ConnectionConstraint(label: "Hub", maximumSpeedBps: 480_000_000, kind: .hub, source: .ioRegistryObserved)]
        )
        XCTAssertEqual(hub.primaryCause, .hub)
        XCTAssertEqual(hub.confidence, .confirmed)

        let atReference = ConnectionDiagnosisEngine.analyze(currentLinkSpeedBps: 10_000_000_000, referenceMaxSpeedBps: 10_000_000_000, constraints: [])
        XCTAssertEqual(atReference.warningLevel, .info)

        let unknown = ConnectionDiagnosisEngine.analyze(currentLinkSpeedBps: nil, referenceMaxSpeedBps: nil, constraints: [])
        XCTAssertEqual(unknown.primaryCause, .unknown)
        XCTAssertEqual(unknown.confidence, .insufficientEvidence)
    }

    func testCableCompatibilityFlagsOnlyKnownShortfalls() {
        let limited = ConnectionDiagnosisEngine.cableCompatibilityCheck(deviceCapabilityBps: 10_000_000_000, negotiatedBps: 5_000_000_000, powerRequirementWatts: 60, powerCapabilityWatts: 30)
        XCTAssertTrue(limited.dataLimited)
        XCTAssertTrue(limited.powerLimited)

        let unknown = ConnectionDiagnosisEngine.cableCompatibilityCheck(deviceCapabilityBps: nil, negotiatedBps: 5_000_000_000, powerRequirementWatts: nil, powerCapabilityWatts: 30)
        XCTAssertFalse(unknown.dataLimited)
        XCTAssertFalse(unknown.powerLimited)
    }

    // MARK: Export and catalog

    func testSharedExportRedactsNestedIdentifiersAndHomePaths() throws {
        let input: [String: Any] = [
            "label": "SSD",
            "id": "secret",
            "nested": [["serialNumber": "S1", "mountPath": "/Volumes/X", "note": "/Users/someone/Desktop/file"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: input)
        let redacted = try XCTUnwrap(SharedExportSanitizer.redactJSON(data))
        let text = try XCTUnwrap(String(data: redacted, encoding: .utf8))

        XCTAssertTrue(text.contains("\"label\""))
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("S1"))
        XCTAssertFalse(text.contains("/Volumes/X"))
        XCTAssertFalse(text.contains("someone"))
        XCTAssertNil(SharedExportSanitizer.redactJSON(Data("not json".utf8)))
    }

    func testBridgeCatalogRequiresBothIdentifiers() {
        XCTAssertEqual(BridgeCatalog.match(vendorID: 0x152D, productID: 0x0583)?.family, "JMicron JMS583")
        XCTAssertNil(BridgeCatalog.match(vendorID: 0x152D, productID: nil))
        XCTAssertNil(BridgeCatalog.match(vendorID: 0x152D, productID: 0x9999))
    }

    func testLinkExpectationProtocols() {
        XCTAssertEqual(BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: 480_000_000)?.protocolName, "USB 2.0 (480 Mb/s)")
        XCTAssertEqual(BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: 40_000_000_000)?.realisticMaximumMBps, 3200)
        XCTAssertEqual(BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: 10_000_000_000)?.realisticRangeFormatted, "683–1050 MB/s")
        XCTAssertEqual(BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: 12_000_000)?.theoreticalMaxFormatted, "2 MB/s")
    }
}
