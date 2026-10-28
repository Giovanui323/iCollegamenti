import XCTest
@testable import CAVICore

final class HDMIAnalysisTests: XCTestCase {
    private func signal(
        width: Int = 3840,
        height: Int = 2160,
        refresh: Double = 60,
        bitDepth: Int = 8,
        chroma: ChromaSubsampling = .rgb444,
        hdr: Bool = false,
        dsc: Bool = false
    ) -> HDMISignalConfiguration {
        HDMISignalConfiguration(
            width: width,
            height: height,
            refreshRate: refresh,
            bitDepth: bitDepth,
            chroma: chroma,
            isHDRActive: hdr,
            isDSCActive: dsc,
            isVRRActive: false,
            transportType: "HDMI",
            bandwidthRequirement: HDMIBandwidthCalculator.calculate(
                width: width, height: height, refreshRate: refresh,
                bitDepth: bitDepth, chroma: chroma, isDSC: dsc
            )
        )
    }

    // MARK: Bandwidth

    func testChromaSubsamplingReducesBandwidthProportionally() {
        let rgb = HDMIBandwidthCalculator.calculate(width: 3840, height: 2160, refreshRate: 60, bitDepth: 10, chroma: .rgb444, isDSC: false)
        let ycc422 = HDMIBandwidthCalculator.calculate(width: 3840, height: 2160, refreshRate: 60, bitDepth: 10, chroma: .ycbcr422, isDSC: false)
        let ycc420 = HDMIBandwidthCalculator.calculate(width: 3840, height: 2160, refreshRate: 60, bitDepth: 10, chroma: .ycbcr420, isDSC: false)

        XCTAssertEqual(ycc422.totalBandwidthGbps / rgb.totalBandwidthGbps, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(ycc420.totalBandwidthGbps / rgb.totalBandwidthGbps, 0.5, accuracy: 0.0001)
        XCTAssertEqual(rgb.totalBandwidthGbps / rgb.rawBandwidthGbps, 1.25, accuracy: 0.0001)
    }

    func testDSCReportsCompressedEffectiveBandwidth() {
        let plain = HDMIBandwidthCalculator.calculate(width: 7680, height: 4320, refreshRate: 60, bitDepth: 10, chroma: .rgb444, isDSC: false)
        let compressed = HDMIBandwidthCalculator.calculate(width: 7680, height: 4320, refreshRate: 60, bitDepth: 10, chroma: .rgb444, isDSC: true)

        XCTAssertNil(plain.dscBandwidthGbps)
        XCTAssertEqual(plain.effectiveBandwidthGbps, plain.totalBandwidthGbps)
        XCTAssertTrue(compressed.isDSCActive)
        XCTAssertEqual(compressed.effectiveBandwidthGbps, plain.totalBandwidthGbps / 3, accuracy: 0.0001)
    }

    func testHeadroomLevels() {
        XCTAssertEqual(HDMIBandwidthCalculator.headroom(required: 10, available: 15).headroomLevel, .comfortable)
        XCTAssertEqual(HDMIBandwidthCalculator.headroom(required: 10, available: 11.5).headroomLevel, .adequate)
        XCTAssertEqual(HDMIBandwidthCalculator.headroom(required: 10, available: 10.6).headroomLevel, .tight)
        XCTAssertEqual(HDMIBandwidthCalculator.headroom(required: 10, available: 10.2).headroomLevel, .critical)
        XCTAssertEqual(HDMIBandwidthCalculator.headroom(required: 10, available: 9).headroomLevel, .exceeded)
        XCTAssertEqual(HDMIBandwidthCalculator.headroom(required: 10, available: 15).headroomPercent, 50, accuracy: 0.0001)
    }

    func testHeadroomWithZeroRequirementIsFinite() {
        let fits = HDMIBandwidthCalculator.headroom(required: 0, available: 18)
        XCTAssertTrue(fits.headroomPercent.isFinite)
        XCTAssertEqual(fits.headroomLevel, .comfortable)

        let nothing = HDMIBandwidthCalculator.headroom(required: 0, available: 0)
        XCTAssertTrue(nothing.headroomPercent.isFinite)
        XCTAssertEqual(nothing.headroomLevel, .exceeded)
    }

    func testMinimumStandardStaysOnTheHDMILadder() {
        func standard(_ width: Int, _ height: Int, _ refresh: Double, _ depth: Int = 8, _ chroma: ChromaSubsampling = .rgb444) -> HDMIStandard {
            HDMIBandwidthCalculator.minimumStandard(for: HDMIBandwidthCalculator.calculate(
                width: width, height: height, refreshRate: refresh, bitDepth: depth, chroma: chroma, isDSC: false
            ))
        }
        XCTAssertEqual(standard(1920, 1080, 60), .hdmi14)
        XCTAssertEqual(standard(3840, 2160, 60), .hdmi20)
        // ~29.9 Gb/s: needs HDMI 2.1, never "DisplayPort 1.4" as an HDMI requirement.
        XCTAssertEqual(standard(3840, 2160, 120), .hdmi21)
        XCTAssertEqual(standard(7680, 4320, 60, 10), .dp21)
    }

    func testMaximumModePicksTheLargestThatFits() {
        let modes = [
            HDMIBandwidthCalculator.calculate(width: 1920, height: 1080, refreshRate: 60, bitDepth: 8, chroma: .rgb444, isDSC: false),
            HDMIBandwidthCalculator.calculate(width: 3840, height: 2160, refreshRate: 60, bitDepth: 8, chroma: .rgb444, isDSC: false),
            HDMIBandwidthCalculator.calculate(width: 3840, height: 2160, refreshRate: 120, bitDepth: 8, chroma: .rgb444, isDSC: false)
        ]
        XCTAssertEqual(HDMIBandwidthCalculator.maximumMode(within: 18, modes: modes)?.refreshRate, 60)
        XCTAssertEqual(HDMIBandwidthCalculator.maximumMode(within: 18, modes: modes)?.width, 3840)
        XCTAssertNil(HDMIBandwidthCalculator.maximumMode(within: 1, modes: modes))
    }

    // MARK: Compatibility matrix

    func testCompatibilityMatrixPricesSubsampledModesCorrectly() throws {
        let rows = HDMICompatibilityMatrixGenerator.standardModes()
        let rgb = try XCTUnwrap(rows.first { $0.modeLabel == "4K 60Hz HDR" })
        let ycc420 = try XCTUnwrap(rows.first { $0.modeLabel == "4K 60Hz HDR 4:2:0" })

        XCTAssertEqual(ycc420.requiredBandwidthGbps, rgb.requiredBandwidthGbps / 2, accuracy: 0.0001)
        XCTAssertTrue(rows.allSatisfy { $0.result == .untested })
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        for row in rows {
            let expected = HDMIBandwidthCalculator.calculate(
                width: row.width, height: row.height, refreshRate: row.refreshRate,
                bitDepth: row.bitDepth, chroma: row.chroma, isDSC: false
            ).totalBandwidthGbps
            XCTAssertEqual(row.requiredBandwidthGbps, expected, accuracy: 0.0001, row.modeLabel)
        }
    }

    func testUpdateResultChangesOnlyTheMatchingRow() {
        var rows = HDMICompatibilityMatrixGenerator.standardModes()
        let target = rows[3]
        HDMICompatibilityMatrixGenerator.updateResult(matrix: &rows, modeID: target.id, result: .pass)
        XCTAssertEqual(rows[3].result, .pass)
        XCTAssertEqual(rows[3].modeLabel, target.modeLabel)
        XCTAssertEqual(rows.filter { $0.result == .pass }.count, 1)

        HDMICompatibilityMatrixGenerator.updateResult(matrix: &rows, modeID: UUID(), result: .fail)
        XCTAssertFalse(rows.contains { $0.result == .fail })
    }

    // MARK: Scoring

    func testConnectionScoreStaysWithinBounds() {
        let exceeded = HDMIScoringEngine.connectionScore(
            bandwidthHeadroom: HDMIBandwidthCalculator.headroom(required: 20, available: 5),
            stabilityScore: 100, isHDR: false, audioFormats: [], disconnects: 0
        )
        XCTAssertEqual(exceeded.bandwidth, 0)
        XCTAssertGreaterThanOrEqual(exceeded.overall, 0)

        let infinite = BandwidthHeadroom(requiredGbps: 0, availableGbps: 1, headroomPercent: .infinity, headroomLevel: .comfortable)
        let score = HDMIScoringEngine.connectionScore(bandwidthHeadroom: infinite, stabilityScore: 100, isHDR: true, audioFormats: [], disconnects: 0)
        XCTAssertLessThanOrEqual(score.bandwidth, 100)

        let unstable = HDMIScoringEngine.connectionScore(
            bandwidthHeadroom: HDMIBandwidthCalculator.headroom(required: 10, available: 20),
            stabilityScore: 0, isHDR: false, audioFormats: [], disconnects: Int.max
        )
        XCTAssertEqual(unstable.stability, 0)
        XCTAssertEqual(unstable.handshake, 0)
    }

    func testConnectionScoreLevels() {
        let headroom = HDMIBandwidthCalculator.headroom(required: 10, available: 20)
        let lpcm = CTAAudioFormat(formatName: "LPCM", maxChannels: 2, sampleRates: [48000], bitDepths: [24], maxBitrate: nil)
        let best = HDMIScoringEngine.connectionScore(bandwidthHeadroom: headroom, stabilityScore: 100, isHDR: true, audioFormats: Array(repeating: lpcm, count: 4), disconnects: 0)
        XCTAssertEqual(best.overall, 100)
        XCTAssertEqual(best.level, .excellent)

        let poor = HDMIScoringEngine.connectionScore(bandwidthHeadroom: headroom, stabilityScore: 0, isHDR: false, audioFormats: [], disconnects: 4)
        XCTAssertLessThan(poor.overall, 75)
    }

    func testGamingAndProfessionalScoresAddUp() {
        let gaming = HDMIScoringEngine.gamingScore(supports4K120: true, supportsVRR: true, supportsHDR: true, chromaQuality: .rgb444, bitDepth: 10, stabilityScore: 100)
        XCTAssertEqual(gaming.overall, 100)
        let basic = HDMIScoringEngine.gamingScore(supports4K120: false, supportsVRR: false, supportsHDR: false, chromaQuality: .ycbcr420, bitDepth: 8, stabilityScore: 500)
        XCTAssertEqual(basic.overall, 10, "Stability input is clamped to 100")

        let professional = HDMIScoringEngine.professionalScore(rgbFull: true, is10Bit: false, supportsHDR: true, maxResolution: "4K", maxRefresh: "60Hz", isCompressed: true, edidComplete: true)
        XCTAssertEqual(professional.overall, 60)
    }

    func testObservedScoresReflectTheActiveSignalNotAPerfectDefault() {
        let modest = signal(width: 1920, height: 1080, refresh: 60, bitDepth: 8, chroma: .ycbcr422)
        let modestGaming = HDMIScoringEngine.observedGamingScore(signal: modest, edid: nil)
        XCTAssertEqual(modestGaming.overall, 0)
        XCTAssertFalse(modestGaming.supports4K120)
        XCTAssertFalse(modestGaming.supportsHighRefresh)

        let modestPro = HDMIScoringEngine.observedProfessionalScore(signal: modest, edid: nil)
        XCTAssertEqual(modestPro.overall, 20, "Only 'uncompressed' is observed")
        XCTAssertFalse(modestPro.edidComplete)
        XCTAssertEqual(modestPro.maxResolution, "1920x1080")

        let best = signal(width: 3840, height: 2160, refresh: 120, bitDepth: 10, chroma: .rgb444, hdr: true)
        let bestGaming = HDMIScoringEngine.observedGamingScore(signal: best, edid: nil)
        // 25 + 20 (HDR) + 15 + 10 = 70 of the 90 measurable points; VRR is not observed.
        XCTAssertEqual(bestGaming.overall, 78)
        XCTAssertTrue(bestGaming.supports4K120)
        XCTAssertTrue(bestGaming.supportsHDR)
        XCTAssertFalse(bestGaming.supportsVRR)
    }
}
