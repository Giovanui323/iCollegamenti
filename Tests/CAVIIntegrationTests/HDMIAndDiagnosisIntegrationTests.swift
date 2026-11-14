import XCTest
import CAVICore
@testable import CAVI

@MainActor
final class HDMIAndDiagnosisIntegrationTests: XCTestCase {
    func testMissingReferenceGetsItsOwnMessage() {
        let device = DriveDevice(volumeName: "SSD", mountPath: "/Volumes/SSD", bsdName: "disk9s1", negotiatedSpeedBps: 10_000_000_000)
        let analysis = BottleneckAnalyzerService().analyze(device: device, referenceDevice: nil, language: .english)

        XCTAssertEqual(analysis.headline, "Missing reference measurement")
        XCTAssertTrue(analysis.detailedMessage.contains("10 Gb/s"))
        XCTAssertTrue(analysis.diagnosis.lacksReferenceMeasurement)
    }

    func testUnavailableLinkKeepsItsOwnMessage() {
        let device = DriveDevice(volumeName: "SSD", mountPath: "/Volumes/SSD", bsdName: "disk9s1", negotiatedSpeedBps: nil)
        let analysis = BottleneckAnalyzerService().analyze(device: device, referenceDevice: nil, language: .italian)
        XCTAssertEqual(analysis.headline, "Velocità del link non disponibile")
    }

    func testDisplayDeviceTakesItsCapabilitiesFromTheEDID() throws {
        var display = HDMIDisplayDevice(
            displayID: 1, displayName: "Monitor", widthPixels: 3840, heightPixels: 2160,
            refreshRateHz: 60, isHDRSupported: true, colorDepthBits: 10,
            connectionTransport: "HDMI", estimatedBandwidthGbps: 15, cableGrade: .hdmi2_0
        )
        var bytes: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x10, 0xAC]
        bytes += Array(repeating: 0, count: 118)
        let edid = try XCTUnwrap(EDIDParser.parse(bytes))

        display.apply(edid: edid)
        XCTAssertEqual(display.manufacturerFromEDID, "Dell")
        XCTAssertNotNil(display.parsedEDID)
        XCTAssertFalse(display.supportsHDR10)
        XCTAssertNil(display.vrrRange)
    }

    func testCableRecordIsBuiltOnlyFromMeasurements() throws {
        XCTAssertNil(HDMICableTestRecord.measured(displayName: "TV", highestVerifiedMode: nil, capabilityScore: nil, stress: nil))

        let mode = HDMICapabilityTestEntry(
            id: UUID(), modeDescription: "3840x2160@60Hz", width: 3840, height: 2160, refreshRate: 60,
            bitDepth: 8, chroma: .rgb444, isHDR: false, bandwidthGbps: 14.9, status: .pass,
            durationSeconds: 5, disconnects: 0, notes: nil
        )
        let stress = HDMIStressTestResult(
            id: UUID(), mode: "3840x2160@60Hz", durationSeconds: 300, disconnects: 1, renegotiations: 0,
            modeChanges: 0, hdcpFailures: 0, stabilityScore: 70, events: []
        )
        let record = try XCTUnwrap(HDMICableTestRecord.measured(displayName: "TV", highestVerifiedMode: mode, capabilityScore: 90, stress: stress))
        XCTAssertEqual(record.maximumVerifiedMode, "3840x2160@60Hz")
        XCTAssertEqual(record.maximumBandwidthGbps, 14.9)
        XCTAssertEqual(record.stressTestDuration, 300)
        XCTAssertEqual(record.disconnects, 1)
        XCTAssertEqual(record.stabilityScore, 70)
        XCTAssertEqual(record.overallScore, 80)

        let stressOnly = try XCTUnwrap(HDMICableTestRecord.measured(displayName: "TV", highestVerifiedMode: nil, capabilityScore: nil, stress: stress))
        XCTAssertEqual(stressOnly.maximumVerifiedMode, "—")
        XCTAssertEqual(stressOnly.maximumBandwidthGbps, 0)
        XCTAssertEqual(stressOnly.overallScore, 70)
    }
}
