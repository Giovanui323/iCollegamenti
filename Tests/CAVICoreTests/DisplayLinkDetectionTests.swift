import XCTest
@testable import CAVICore

final class DisplayLinkDetectionTests: XCTestCase {
    private func observation(
        port: String? = "USB-C",
        active: Bool = true,
        hpd: Bool = true,
        tunneled: Bool = false,
        laneRateHz: UInt64? = 8_100_000_000,
        lanes: Int? = 4,
        maxLanes: Int? = 4,
        dfp: String? = nil,
        name: String? = "LG HDR 4K",
        productID: Int? = 30543,
        serial: Int? = 203829
    ) -> DisplayPortTransportObservation {
        DisplayPortTransportObservation(
            portTypeDescription: port, portNumber: 1, isActive: active, isHotPlugHigh: hpd,
            isTunneled: tunneled, laneRateHz: laneRateHz, laneCount: lanes, maxLaneCount: maxLanes,
            downstreamPortTypeDescription: dfp, productName: name, productID: productID, serialNumber: serial
        )
    }

    func testClassifiesPhysicalPort() {
        XCTAssertEqual(DisplayLinkClassifier.kind(for: observation(port: "HDMI", dfp: "HDMI")), .builtInHDMIPort)
        XCTAssertEqual(DisplayLinkClassifier.kind(for: observation(port: "USB-C")), .usbCDisplayPortAltMode)
        XCTAssertEqual(DisplayLinkClassifier.kind(for: observation(port: "USB-C", dfp: "DisplayPort")), .usbCDisplayPortAltMode)
        XCTAssertEqual(DisplayLinkClassifier.kind(for: observation(port: "USB-C", dfp: "HDMI")), .usbCToHDMIAdapter)
        XCTAssertEqual(DisplayLinkClassifier.kind(for: observation(port: "USB-C", tunneled: true)), .thunderboltOrUSB4Tunnel)
        XCTAssertEqual(DisplayLinkClassifier.kind(for: observation(port: nil)), .unknown)
        XCTAssertTrue(DisplayConnectionKind.usbCDisplayPortAltMode.isDisplayPortCable)
        XCTAssertFalse(DisplayConnectionKind.builtInHDMIPort.isDisplayPortCable)
    }

    func testHBR3FourLaneBandwidthUses8b10b() throws {
        let link = DisplayLinkClassifier.assess(observation())
        XCTAssertEqual(link.generation, "HBR3")
        XCTAssertEqual(try XCTUnwrap(link.rawGbps), 32.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(link.effectiveGbps), 25.92, accuracy: 0.001)
        XCTAssertFalse(link.isLaneReduced)
        XCTAssertEqual(link.summary(italian: true), "USB-C → DisplayPort (Alt Mode) · HBR3 8.1 Gb/s × 4 lane (25.9 Gb/s utili)")
    }

    func testUHBRUses128b132bAndDetectsReducedLanes() throws {
        let link = DisplayLinkClassifier.assess(observation(laneRateHz: 20_000_000_000, lanes: 2, maxLanes: 4))
        XCTAssertEqual(link.generation, "UHBR20")
        XCTAssertEqual(try XCTUnwrap(link.effectiveGbps), 40 * 128 / 132, accuracy: 0.001)
        XCTAssertTrue(link.isLaneReduced)
    }

    func testLaneRateFallsBackToDescription() throws {
        let raw = DisplayPortTransportObservation(
            portTypeDescription: "USB-C", isActive: true, isHotPlugHigh: true, isTunneled: false,
            laneRateHz: nil, linkRateDescription: "5.4 Gbps (HBR2)", laneCount: 2
        )
        let link = DisplayLinkClassifier.assess(raw)
        XCTAssertEqual(link.generation, "HBR2")
        XCTAssertEqual(try XCTUnwrap(link.rawGbps), 10.8, accuracy: 0.001)
    }

    func testMatcherPrefersExactEDIDIdentityAndIgnoresInactiveLinks() {
        let lg = observation(port: "USB-C")
        let other = observation(port: "HDMI", name: "DELL U2723QE", productID: 41_234, serial: 1)
        let stale = observation(port: "USB-C", active: false, name: "LG HDR 4K")
        let found = DisplayLinkMatcher.observation(for: (30543, 203829, nil), in: [stale, other, lg], externalDisplayCount: 2)
        XCTAssertEqual(found, lg)
        let dell = DisplayLinkMatcher.observation(for: (nil, nil, "dell u2723qe"), in: [lg, other], externalDisplayCount: 2)
        XCTAssertEqual(dell, other)
    }

    func testMatcherNeverGuessesWithSeveralDisplays() {
        let a = observation(productID: 1, serial: 1)
        let b = observation(productID: 2, serial: 2)
        XCTAssertNil(DisplayLinkMatcher.observation(for: (nil, nil, nil), in: [a, b], externalDisplayCount: 2))
        let single = observation(productID: nil, serial: nil)
        XCTAssertEqual(DisplayLinkMatcher.observation(for: (999, 0, nil), in: [single], externalDisplayCount: 1), single)
    }

    func testBillboardDetection() {
        XCTAssertTrue(USBBillboardPolicy.isBillboard(deviceClass: 17, productName: "USB-C Adapter"))
        XCTAssertTrue(USBBillboardPolicy.isBillboard(deviceClass: nil, productName: "Billboard Device"))
        XCTAssertFalse(USBBillboardPolicy.isBillboard(deviceClass: 0, productName: "Portable SSD"))
        XCTAssertEqual(USBBillboardPolicy.deviceClass(fromPropertyValue: "17"), 17)
        XCTAssertEqual(USBBillboardPolicy.deviceClass(fromPropertyValue: "0x11"), 17)
        XCTAssertNil(USBBillboardPolicy.deviceClass(fromPropertyValue: nil))
    }

    func testBillboardLabelReflectsLiveLink() {
        XCTAssertEqual(USBBillboardPolicy.historyLabel(liveLink: nil), "Cavo/adattatore USB-C video (Alt Mode)")
        let dp = DisplayLinkClassifier.assess(observation())
        XCTAssertEqual(USBBillboardPolicy.historyLabel(liveLink: dp), "Cavo USB-C → DisplayPort (Alt Mode)")
        let hdmiPort = DisplayLinkClassifier.assess(observation(port: "HDMI"))
        XCTAssertEqual(USBBillboardPolicy.historyLabel(liveLink: hdmiPort), "Cavo/adattatore USB-C video (Alt Mode)")
    }
}
