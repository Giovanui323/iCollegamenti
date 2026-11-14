import XCTest
@testable import CAVI
import CAVICore

final class DisplayPortDetectionIntegrationTests: XCTestCase {
    /// Properties as macOS 27 reports them for an LG HDR 4K on a MacBook Pro HDMI port.
    private let hdmiPortRegistry: [String: Any] = [
        "ParentPortTypeDescription": "HDMI",
        "ParentPortNumber": NSNumber(value: 3),
        "Active": true,
        "HPD_StateDescription": "High",
        "Tunneled": false,
        "NominalSignalingFrequenciesHz": [NSNumber(value: 8_100_000_000 as UInt64)],
        "LinkRateDescription": "8.1 Gbps (HBR3)",
        "LaneCount": NSNumber(value: 4),
        "MaxLaneCount": NSNumber(value: 4),
        "ProductName": "LG HDR 4K",
        "ProductID": NSNumber(value: 30543),
        "SerialNumber": NSNumber(value: 203829),
        "ManufacturerName": "GSM",
        "Metadata": ["DFP Type Description": "HDMI"] as [String: Any],
    ]

    func testMapsRegistryPropertiesForBuiltInHDMIPort() throws {
        let observation = DisplayPortTransportReader.observation(from: hdmiPortRegistry)
        XCTAssertTrue(observation.isLive)
        XCTAssertEqual(observation.portNumber, 3)
        XCTAssertEqual(observation.productID, 30543)
        XCTAssertEqual(observation.serialNumber, 203829)
        XCTAssertEqual(observation.downstreamPortTypeDescription, "HDMI")
        let link = DisplayLinkClassifier.assess(observation)
        XCTAssertEqual(link.kind, .builtInHDMIPort)
        XCTAssertEqual(link.generation, "HBR3")
        XCTAssertEqual(link.laneCount, 4)
    }

    func testMapsUSBCAltModeAndHotPlugStateNumber() {
        var registry = hdmiPortRegistry
        registry["ParentPortTypeDescription"] = "USB-C"
        registry["Metadata"] = ["DFP Type Description": "DisplayPort"] as [String: Any]
        registry["HPD_StateDescription"] = nil
        registry["HPD_State"] = NSNumber(value: 2)
        let observation = DisplayPortTransportReader.observation(from: registry)
        XCTAssertTrue(observation.isHotPlugHigh)
        XCTAssertEqual(DisplayLinkClassifier.kind(for: observation), .usbCDisplayPortAltMode)

        registry["HPD_State"] = NSNumber(value: 0)
        XCTAssertFalse(DisplayPortTransportReader.observation(from: registry).isLive)
    }

    func testBillboardPeripheralIsRecognizedFromUSBClass() {
        let billboard = DriveDevice(
            productName: "USB-C Multiport Adapter",
            isStorageDevice: false,
            connectionSnapshot: ConnectionSnapshot(protocolName: "USB", technicalProperties: [TechnicalProperty(key: "bDeviceClass", value: "17")])
        )
        XCTAssertTrue(billboard.isUSBBillboard)
        let ssd = DriveDevice(productName: "Billboard SSD", isStorageDevice: true)
        XCTAssertFalse(ssd.isUSBBillboard)
    }

    func testLegacyBillboardEntryIsReclassifiedAsVideo() {
        let legacy = CableTestResult(
            cableLabel: "Billboard Device — USB 1.1",
            deviceName: "Billboard Device",
            deviceVendorID: 1507,
            deviceProductID: 3841,
            linkSpeedBps: 12_000_000,
            topologyDescription: "Mac → Billboard Device",
            connectionFingerprint: "fp"
        )
        let fixed = TestHistoryStore.reclassifyingBillboard(legacy)
        XCTAssertEqual(fixed.id, legacy.id)
        XCTAssertEqual(fixed.category, .video)
        XCTAssertEqual(fixed.cableLabel, "Cavo/adattatore USB-C video (Alt Mode)")
        XCTAssertEqual(fixed.linkSpeedBps, 0)
        XCTAssertEqual(fixed.connectionFingerprint, "fp")

        let renamed = CableTestResult(cableLabel: "Cavo DP scrivania", deviceName: "Billboard Device", linkSpeedBps: 12_000_000)
        XCTAssertEqual(TestHistoryStore.reclassifyingBillboard(renamed).cableLabel, "Cavo DP scrivania")

        let ssd = CableTestResult(cableLabel: "Portable SSD", deviceName: "Portable SSD", linkSpeedBps: 10_000_000_000)
        XCTAssertEqual(TestHistoryStore.reclassifyingBillboard(ssd), ssd)
    }
}
