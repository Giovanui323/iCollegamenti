import XCTest
@testable import CAVICore

final class USBTopologyAndBandwidthTests: XCTestCase {
    func testCollapsesControllerAndRootHubToOneMacBreadcrumb() {
        let device = USBStorageReconciler.reconcile(
            USBStorageFixtures.mountedSanDiskObservedThroughTwoLayers()
        ).physicalDevices[0]

        let path = USBTopologyNormalizer.presentationPath(for: device)

        XCTAssertEqual(path.labels.first, "Mac")
        XCTAssertFalse(path.labels.joined(separator: " → ").contains("Mac → Mac"))
        XCTAssertTrue(path.technicalNodes.contains(where: \.isController))
        XCTAssertTrue(path.technicalNodes.contains(where: \.isRootHub))
        XCTAssertTrue(path.technicalNodes.contains(where: { $0.kind == .externalHub }))
    }

    func testOneFiveGigabitDriveObservedThroughLayersIsOneConsumerAtOneHundredPercent() throws {
        let graph = USBStorageReconciler.reconcile(
            USBStorageFixtures.mountedSanDiskObservedThroughTwoLayers()
        )

        let budget = try XCTUnwrap(
            BandwidthAccounting.budget(forUplinkID: "hub-external-1", in: graph)
        )

        XCTAssertEqual(budget.consumers.map(\.requestedSpeedBps), [USBStorageFixtures.fiveGigabits])
        XCTAssertEqual(budget.potentialDemandBps, USBStorageFixtures.fiveGigabits)
        XCTAssertEqual(budget.saturationPercent, 100)
    }

    func testThreeDifferentFiveGigabitDrivesOnOneUplinkAreThreeHundredPercent() throws {
        let graph = USBStorageReconciler.reconcile(
            USBStorageFixtures.threeDevicesOnFiveGigabitHub()
        )

        let budget = try XCTUnwrap(
            BandwidthAccounting.budget(forUplinkID: "hub-external-1", in: graph)
        )

        XCTAssertEqual(budget.consumers.count, 3)
        XCTAssertEqual(budget.potentialDemandBps, 15_000_000_000)
        XCTAssertEqual(budget.saturationPercent, 300)
    }

    func testADeviceWithDiskPartitionAndVolumeIsNotCountedThreeTimes() throws {
        let graph = USBStorageReconciler.reconcile(
            USBStorageFixtures.mountedSanDiskObservedThroughTwoLayers()
        )

        let budget = try XCTUnwrap(
            BandwidthAccounting.budget(forUplinkID: "hub-external-1", in: graph)
        )

        XCTAssertEqual(budget.consumers.count, 1)
        XCTAssertEqual(budget.saturationPercent, 100)
    }

    func testNestedHubCapsItsBranchBeforeDemandIsPropagatedUpstream() throws {
        let graph = USBStorageReconciler.reconcile(
            USBStorageFixtures.nestedHubsWithTwoFiveGigabitDrives()
        )

        let lowerBudget = try XCTUnwrap(BandwidthAccounting.budget(forUplinkID: "hub-b-5g", in: graph))
        XCTAssertEqual(lowerBudget.potentialDemandBps, 10_000_000_000)
        XCTAssertEqual(lowerBudget.saturationPercent, 200)

        let upperBudget = try XCTUnwrap(BandwidthAccounting.budget(forUplinkID: "hub-a-10g", in: graph))
        XCTAssertEqual(upperBudget.consumers.count, 1)
        XCTAssertEqual(upperBudget.potentialDemandBps, USBStorageFixtures.fiveGigabits)
        XCTAssertEqual(upperBudget.saturationPercent, 50)
    }
}
