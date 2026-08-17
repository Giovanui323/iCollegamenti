import XCTest
@testable import CAVICore

final class USBStorageReconciliationTests: XCTestCase {
    func testReconcilesOneMountedFlashDriveObservedThroughUSBAndMediaLayers() throws {
        let graph = USBStorageReconciler.reconcile(
            USBStorageFixtures.mountedSanDiskObservedThroughTwoLayers()
        )

        XCTAssertEqual(graph.physicalDevices.count, 1)
        let device = try XCTUnwrap(graph.physicalDevices.first)
        XCTAssertEqual(device.disks.map(\.bsdName), ["disk4"])
        XCTAssertEqual(device.disks[0].partitions.map(\.bsdName), ["disk4s1"])
        XCTAssertEqual(device.disks[0].partitions[0].volumes.map(\.mountPath), ["/Volumes/SANDISK"])
    }

    func testCollapsesDuplicateWholeDiskObservationsFromOneRefresh() throws {
        let graph = USBStorageReconciler.reconcile(
            USBStorageFixtures.mountedSanDiskWithDuplicateWholeDiskObservation()
        )

        let device = try XCTUnwrap(graph.physicalDevices.first)
        XCTAssertEqual(device.disks.map(\.bsdName), ["disk4"])
        XCTAssertEqual(device.disks[0].capacityBytes, 64_000_000_000)
    }

    func testDoesNotMergeIdenticalVendorAndProductAtDifferentLocations() {
        let graph = USBStorageReconciler.reconcile(
            USBStorageFixtures.identicalVIDPIDAtDifferentLocations()
        )

        XCTAssertEqual(graph.physicalDevices.count, 2)
    }

    func testUsesRegistryPathWhenSerialIsUnavailable() {
        let graph = USBStorageReconciler.reconcile(
            USBStorageFixtures.serialLessDriveObservedThroughTwoLayers()
        )

        XCTAssertEqual(graph.physicalDevices.count, 1)
        XCTAssertEqual(graph.physicalDevices[0].disks.map(\.bsdName), ["disk5"])
    }

    func testDoesNotMergeSameSerialWhenLocationsConflictInOneSnapshot() {
        let graph = USBStorageReconciler.reconcile(
            USBStorageFixtures.sameSerialAtConflictingLocations()
        )

        XCTAssertEqual(graph.physicalDevices.count, 2)
        XCTAssertFalse(USBStorageReconciler.areEquivalent(
            graph.physicalDevices[0],
            graph.physicalDevices[1]
        ))
    }

    func testKeepsTwoPartitionsAndVolumesBelowOnePhysicalDevice() {
        let device = USBStorageReconciler.reconcile(
            USBStorageFixtures.driveWithTwoMountedPartitions()
        ).physicalDevices[0]

        XCTAssertEqual(device.disks.count, 1)
        XCTAssertEqual(device.disks[0].partitions.count, 2)
        XCTAssertEqual(device.disks[0].partitions.flatMap(\.volumes).count, 2)
    }

    func testAssociatesStorageBehindUSBBridgeWithOneEnclosure() {
        let graph = USBStorageReconciler.reconcile(USBStorageFixtures.usbNVMeEnclosure())

        XCTAssertEqual(graph.physicalDevices.count, 1)
        XCTAssertEqual(graph.physicalDevices[0].disks.map(\.bsdName), ["disk8"])
    }

    func testSelectsMountedPartitionInsteadOfWholeDiskForBenchmark() {
        let device = USBStorageReconciler.reconcile(
            USBStorageFixtures.mountedSanDiskObservedThroughTwoLayers()
        ).physicalDevices[0]

        XCTAssertEqual(StorageVolumeSelection.benchmarkVolume(for: device)?.bsdName, "disk4s1")
        XCTAssertEqual(StorageVolumeSelection.benchmarkVolume(for: device)?.mountPath, "/Volumes/SANDISK")
        XCTAssertNil(StorageVolumeSelection.mountTarget(for: device))
    }

    func testSelectsUnmountedPartitionForMountAndNeverWholeDisk() {
        let device = USBStorageReconciler.reconcile(
            USBStorageFixtures.unmountedPartitionedDrive()
        ).physicalDevices[0]

        XCTAssertNil(StorageVolumeSelection.benchmarkVolume(for: device))
        XCTAssertEqual(StorageVolumeSelection.mountTarget(for: device)?.bsdName, "disk6s1")
        XCTAssertNotEqual(StorageVolumeSelection.mountTarget(for: device)?.bsdName, "disk6")
    }

    func testKeepsExplicitMountTargetSeparateFromMountedBenchmarkVolume() {
        let device = USBStorageReconciler.reconcile(
            USBStorageFixtures.driveWithOneMountedAndOneUnmountedPartition()
        ).physicalDevices[0]

        XCTAssertEqual(StorageVolumeSelection.benchmarkVolume(for: device)?.bsdName, "disk4s1")
        XCTAssertEqual(
            StorageVolumeSelection.mountTarget(for: device, partitionBSDName: "disk4s2")?.bsdName,
            "disk4s2"
        )
    }
}
