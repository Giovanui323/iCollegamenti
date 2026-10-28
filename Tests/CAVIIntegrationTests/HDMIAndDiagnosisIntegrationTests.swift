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
}
