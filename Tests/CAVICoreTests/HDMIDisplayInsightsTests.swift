import XCTest
@testable import CAVICore

final class HDMIDisplayInsightsTests: XCTestCase {
    private func parsed(_ bytes: [UInt8] = EDIDFixture.withChecksums(EDIDFixture.fullEDID)) throws -> ParsedEDID {
        try XCTUnwrap(EDIDParser.parse(bytes))
    }

    private func signal(width: Int = 3840, height: Int = 2160, refresh: Double = 60, depth: Int = 8, chroma: ChromaSubsampling = .rgb444, hdr: Bool = false) -> HDMISignalConfiguration {
        HDMISignalConfiguration(
            width: width, height: height, refreshRate: refresh, bitDepth: depth, chroma: chroma,
            isHDRActive: hdr, isDSCActive: false, isVRRActive: false, transportType: "HDMI",
            bandwidthRequirement: HDMIBandwidthCalculator.calculate(width: width, height: height, refreshRate: refresh, bitDepth: depth, chroma: chroma, isDSC: false)
        )
    }

    private func stress(seconds: Int = 60, disconnects: Int = 0, renegotiations: Int = 0, modeChanges: Int = 0) -> HDMIStressTestResult {
        HDMIStressTestResult(
            id: UUID(), mode: "3840x2160@60Hz", durationSeconds: seconds,
            disconnects: disconnects, renegotiations: renegotiations, modeChanges: modeChanges, hdcpFailures: 0,
            stabilityScore: max(0, 100 - disconnects * 30 - renegotiations * 15 - modeChanges * 10),
            events: []
        )
    }

    private func entry(_ width: Int, _ height: Int, _ refresh: Double, _ status: HDMICapabilityTestStatus) -> HDMICapabilityTestEntry {
        HDMICapabilityTestEntry(
            id: UUID(), modeDescription: "\(width)x\(height)", width: width, height: height, refreshRate: refresh,
            bitDepth: 8, chroma: .rgb444, isHDR: false, bandwidthGbps: 0, status: status,
            durationSeconds: 5, disconnects: 0, notes: nil
        )
    }

    // MARK: EDID-derived capabilities

    func testChecksumValidationCoversEveryPresentBlock() throws {
        XCTAssertTrue(try parsed().isChecksumValid)

        var corruptBase = EDIDFixture.withChecksums(EDIDFixture.fullEDID)
        corruptBase[20] ^= 0x01
        XCTAssertFalse(try parsed(corruptBase).isChecksumValid)

        var corruptExtension = EDIDFixture.withChecksums(EDIDFixture.fullEDID)
        corruptExtension[200] ^= 0x01
        XCTAssertFalse(try parsed(corruptExtension).isChecksumValid)
    }

    func testHDRFlagsAndLinkCapacity() throws {
        let edid = try parsed()
        XCTAssertTrue(edid.supportsHDR10)
        XCTAssertTrue(edid.supportsHLG)
        // HDMI Forum block: 600 MHz TMDS → 18 Gb/s; no FRL in the base fixture.
        XCTAssertNil(edid.ctaExtension?.hdmiVendorBlock?.maxFRLRateGbps)
        XCTAssertEqual(try XCTUnwrap(edid.advertisedLinkCapacityGbps), 18, accuracy: 0.0001)

        let baseOnly = try parsed(EDIDFixture.withChecksums(EDIDFixture.baseBlock(extensionCount: 0)))
        XCTAssertNil(baseOnly.advertisedLinkCapacityGbps)
        XCTAssertFalse(baseOnly.supportsHDR10)
    }

    func testFRLRateRaisesTheLinkCapacity() throws {
        var bytes = EDIDFixture.fullEDID
        // Locate the HF-VSDB OUI (D8 5D C4) in the CTA block and set Max_FRL_Rate = 6 (48 Gb/s).
        let ouiIndex = try XCTUnwrap((128..<253).first { bytes[$0] == 0xD8 && bytes[$0 + 1] == 0x5D && bytes[$0 + 2] == 0xC4 })
        bytes[ouiIndex + 7] = 0x60
        let edid = try parsed(EDIDFixture.withChecksums(bytes))
        XCTAssertEqual(edid.ctaExtension?.hdmiVendorBlock?.maxFRLRateGbps, 48)
        XCTAssertEqual(edid.ctaExtension?.hdmiVendorBlock?.maxTMDSClockMHz, 600)
        XCTAssertEqual(edid.advertisedLinkCapacityGbps, 48)
    }

    func testForumBlockBeforeHDMIBlockStillMerges() throws {
        let forum = EDIDFixture.dataBlock(tag: 3, [0xD8, 0x5D, 0xC4, 0x01, 120, 0x00, 0x00, 0x50])
        let hdmi = EDIDFixture.dataBlock(tag: 3, [0x03, 0x0C, 0x00, 0x10, 0x00, 0x70, 68])
        let edid = try parsed(EDIDFixture.withChecksums(EDIDFixture.baseBlock() + EDIDFixture.ctaBlock(dataBlocks: forum + hdmi)))
        let vendor = try XCTUnwrap(edid.ctaExtension?.hdmiVendorBlock)
        XCTAssertEqual(vendor.maxTMDSClockMHz, 600)
        XCTAssertEqual(vendor.maxFRLRateGbps, 40)
        XCTAssertTrue(vendor.supportsDeepColor48bit)
    }

    func testAdvertisedModesAreUniqueAndOrderedByPixelRate() throws {
        let modes = try parsed().advertisedModes
        XCTAssertEqual(Set(modes.map(\.id)).count, modes.count)
        XCTAssertEqual(modes.first?.id, "3840x2160@120")
        // 4K60 appears as a DTD (native) and as VIC 97 twice; it is listed once and stays native.
        let uhd60 = try XCTUnwrap(modes.first { $0.id == "3840x2160@60" })
        XCTAssertTrue(uhd60.isNative)
        XCTAssertEqual(uhd60.source, .detailedTiming)
        XCTAssertTrue(modes.contains { $0.id == "1280x1024@60" && $0.source == .standardTiming })
        let rates = modes.map { Double($0.width * $0.height) * $0.refreshRate }
        XCTAssertEqual(rates, rates.sorted(by: >))
    }

    // MARK: Compatibility matrix

    func testMatrixJoinsEDIDModesWithTestResults() throws {
        let edid = try parsed()
        let rows = HDMICompatibilityMatrixGenerator.matrix(edid: edid, testResults: [
            entry(3840, 2160, 59.94, .pass),
            entry(3840, 2160, 120, .fail),
            entry(2560, 1440, 60, .pass)
        ])

        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        XCTAssertEqual(byID["3840x2160@60"]?.testStatus, .pass, "59.94 Hz matches the 60 Hz mode")
        XCTAssertEqual(byID["3840x2160@120"]?.testStatus, .fail)
        XCTAssertEqual(byID["1920x1080@60"]?.testStatus, .untested)
        XCTAssertEqual(byID["2560x1440@60"]?.mode.source, .testedByMac)

        // 18 Gb/s stated: 4K60 8-bit (~14.9) fits, 4K120 (~29.9) does not.
        XCTAssertEqual(byID["3840x2160@60"]?.fitsAdvertisedLink, true)
        XCTAssertEqual(byID["3840x2160@120"]?.fitsAdvertisedLink, false)
    }

    func testMatrixWithoutEDIDUsesOnlyTestedModesAndUnknownCapacity() {
        XCTAssertEqual(HDMICompatibilityMatrixGenerator.matrix(edid: nil, testResults: []), [])
        let rows = HDMICompatibilityMatrixGenerator.matrix(edid: nil, testResults: [entry(1920, 1080, 60, .pass)])
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows[0].fitsAdvertisedLink)
        XCTAssertEqual(rows[0].testStatus, .pass)
    }

    // MARK: Checklist

    func testChecklistOnAHealthyConnection() throws {
        let items = HDMIDiagnosisChecklist.items(signal: signal(hdr: true), edid: try parsed(), stress: stress())
        XCTAssertEqual(items.map(\.kind), HDMIChecklistItemKind.allCases)
        XCTAssertTrue(items.allSatisfy { $0.status == .passed }, "\(items.map { "\($0.kind): \($0.status)" })")
    }

    func testChecklistFlagsRealProblems() throws {
        var corrupt = EDIDFixture.withChecksums(EDIDFixture.fullEDID)
        corrupt[20] ^= 0x01
        let items = HDMIDiagnosisChecklist.items(
            signal: signal(width: 1920, height: 1080, refresh: 60, chroma: .ycbcr420),
            edid: try parsed(corrupt),
            stress: stress(disconnects: 2)
        )
        let status = Dictionary(uniqueKeysWithValues: items.map { ($0.kind, $0.status) })
        XCTAssertEqual(status[.edidIntegrity], .failed)
        XCTAssertEqual(status[.nativeResolution], .attention)
        XCTAssertEqual(status[.chromaQuality], .attention)
        XCTAssertEqual(status[.hdr], .attention, "HDR display running SDR")
        XCTAssertEqual(status[.signalStability], .failed)
        XCTAssertEqual(items.first { $0.kind == .nativeResolution }?.expected, "3840x2160")
    }

    func testChecklistReportsExceededBandwidth() throws {
        let item = HDMIDiagnosisChecklist.items(signal: signal(refresh: 120), edid: try parsed(), stress: nil)
            .first { $0.kind == .linkBandwidth }
        XCTAssertEqual(item?.status, .failed)
        XCTAssertEqual(item?.expected, "18.0 Gb/s")
    }

    func testChecklistWithoutDataIsUnavailableNotPassed() {
        let items = HDMIDiagnosisChecklist.items(signal: nil, edid: nil, stress: nil)
        XCTAssertTrue(items.allSatisfy { $0.status == .unavailable })
        let zeroLength = HDMIDiagnosisChecklist.items(signal: nil, edid: nil, stress: stress(seconds: 0))
        XCTAssertEqual(zeroLength.last?.status, .unavailable)
    }

    func testRenegotiationsAreAttentionNotFailure() {
        let item = HDMIDiagnosisChecklist.items(signal: nil, edid: nil, stress: stress(renegotiations: 1)).last
        XCTAssertEqual(item?.status, .attention)
    }

    // MARK: Connection score

    func testConnectionScoreRequiresAStressTest() throws {
        XCTAssertNil(HDMIScoringEngine.observedConnectionScore(signal: signal(), edid: try parsed(), stress: nil))
        XCTAssertNil(HDMIScoringEngine.observedConnectionScore(signal: signal(), edid: try parsed(), stress: stress(seconds: 0)))
    }

    func testConnectionScoreFromAStableTest() throws {
        let score = try XCTUnwrap(HDMIScoringEngine.observedConnectionScore(signal: signal(), edid: try parsed(), stress: stress()))
        XCTAssertTrue(score.bandwidthObserved)
        // 4K60 needs ~14.9 of 18 Gb/s: ~20.6 % headroom → bandwidth 100.
        XCTAssertEqual(score.bandwidth, 100)
        XCTAssertEqual(score.stability, 100)
        XCTAssertEqual(score.handshake, 100)
        XCTAssertEqual(score.overall, 100)
        XCTAssertEqual(score.level, .excellent)
    }

    func testConnectionScoreWithoutLinkCapacityLeavesBandwidthOut() throws {
        let edid = try parsed(EDIDFixture.withChecksums(EDIDFixture.baseBlock(extensionCount: 0)))
        let score = try XCTUnwrap(HDMIScoringEngine.observedConnectionScore(signal: signal(), edid: edid, stress: stress(disconnects: 1)))
        XCTAssertFalse(score.bandwidthObserved)
        XCTAssertEqual(score.stability, 70)
        XCTAssertEqual(score.handshake, 85)
        XCTAssertEqual(score.overall, 78, "Average of stability and handshake only")
    }

    func testConnectionScoreDropsWithInstability() throws {
        let score = try XCTUnwrap(HDMIScoringEngine.observedConnectionScore(signal: signal(refresh: 120), edid: try parsed(), stress: stress(disconnects: 4, renegotiations: 2)))
        XCTAssertEqual(score.bandwidth, 0, "4K120 exceeds the stated 18 Gb/s")
        XCTAssertEqual(score.stability, 0)
        XCTAssertEqual(score.handshake, 30)
        XCTAssertEqual(score.overall, 10)
        XCTAssertEqual(score.level, .critical)
    }

    // MARK: Missing reference

    func testMissingReferenceIsFlaggedOnlyWhenALinkWasObserved() {
        let noReference = ConnectionDiagnosisEngine.analyze(currentLinkSpeedBps: 5_000_000_000, referenceMaxSpeedBps: nil, constraints: [])
        XCTAssertTrue(noReference.lacksReferenceMeasurement)
        XCTAssertEqual(noReference.primaryCause, .none)

        XCTAssertFalse(ConnectionDiagnosisEngine.analyze(currentLinkSpeedBps: nil, referenceMaxSpeedBps: nil, constraints: []).lacksReferenceMeasurement)
        XCTAssertFalse(ConnectionDiagnosisEngine.analyze(currentLinkSpeedBps: 5_000_000_000, referenceMaxSpeedBps: 5_000_000_000, constraints: []).lacksReferenceMeasurement)
    }
}
