import XCTest
import CAVICore
@testable import CAVI

final class ChargingSnapshotTests: XCTestCase {
    private func snapshot(adapter: Int?, watts: Double?, amps: Double?) -> MacChargingSnapshot {
        MacChargingSnapshot(
            modelIdentifier: "Mac",
            isOnExternalPower: true,
            adapterWatts: adapter,
            batteryWatts: watts,
            batteryVoltageVolts: 12.5,
            batteryCurrentAmps: amps,
            batteryState: "AC Power",
            batteryPercent: 100
        )
    }

    func testFullBatteryFallsBackToAdapterInsteadOfSlowCharging() {
        let full = snapshot(adapter: 96, watts: 0, amps: 0)
        XCTAssertEqual(full.observedWatts, 96)
        XCTAssertEqual(full.assessment, "Alta potenza")
    }

    func testBatteryDischargingOnACIsNotReportedAsCharging() {
        let underLoad = snapshot(adapter: 30, watts: 25, amps: -2)
        XCTAssertEqual(underLoad.observedWatts, 30)
    }

    func testChargingCurrentUsesBatterySidePower() {
        let charging = snapshot(adapter: 96, watts: 54.2, amps: 4.3)
        XCTAssertEqual(charging.observedWatts, 54.2)
    }
}

final class EDIDSelectionTests: XCTestCase {
    private func edid(serial: UInt32) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 128)
        bytes[0...7] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        bytes[12] = UInt8(serial & 0xFF)
        bytes[13] = UInt8((serial >> 8) & 0xFF)
        bytes[14] = UInt8((serial >> 16) & 0xFF)
        bytes[15] = UInt8((serial >> 24) & 0xFF)
        return bytes
    }

    func testIdenticalMonitorsAreToldApartBySerial() {
        let first = edid(serial: 0x0101_0101)
        let second = edid(serial: 0x0202_0202)
        XCTAssertEqual(EDIDReaderService.preferredEDID([first, second], serial: 0x0202_0202), second)
    }

    func testUnknownSerialKeepsTheFirstMatch() {
        let first = edid(serial: 1)
        let second = edid(serial: 2)
        XCTAssertEqual(EDIDReaderService.preferredEDID([first, second], serial: 0), first)
        XCTAssertEqual(EDIDReaderService.preferredEDID([first, second], serial: 99), first)
        XCTAssertNil(EDIDReaderService.preferredEDID([], serial: 1))
    }
}

@MainActor
final class HDMIStressStateTests: XCTestCase {
    func testRunningStateBelongsToTheMonitoredDisplayOnly() {
        let service = HDMIStressTestService()
        service.startStressTest(displayID: 1, durationSeconds: 60)
        defer { service.stopStressTest() }
        XCTAssertTrue(service.isRunning(for: 1))
        XCTAssertFalse(service.isRunning(for: 2))
    }

    func testStoppingWhenIdleDoesNotProduceAResult() {
        let service = HDMIStressTestService()
        service.stopStressTest()
        XCTAssertNil(service.result(for: 0))
        XCTAssertFalse(service.isRunning)
    }
}
