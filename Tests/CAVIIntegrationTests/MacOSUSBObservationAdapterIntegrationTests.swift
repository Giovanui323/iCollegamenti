import XCTest
@testable import CAVI
import CAVICore

final class MacOSUSBObservationAdapterIntegrationTests: XCTestCase {
    @MainActor
    func testDeviceDiscoveryPublishesTheReconciledGraphToTheAppModel() async throws {
        let raw = await MacOSUSBObservationAdapter().collect()
        try XCTSkipIf(raw.registryNodes.allSatisfy { $0.kind != .physicalDevice && $0.kind != .bridge }, "No external USB device is attached.")

        let service = DeviceDiscoveryService()
        service.refreshDevices()
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertFalse(service.reconciledGraph.physicalDevices.isEmpty)
        XCTAssertEqual(
            Set(service.devices.compactMap(\.physicalDeviceID)),
            Set(service.reconciledGraph.physicalDevices.map(\.id))
        )
        XCTAssertEqual(
            Set(USBConnectionDiscoveryService.snapshots(in: service.reconciledGraph).map(\.id)),
            Set(service.reconciledGraph.physicalDevices.map(\.id))
        )
    }

    func testExternalHardwareObservationsRespectGraphInvariants() async throws {
        let raw = await MacOSUSBObservationAdapter().collect()
        let graph = USBStorageReconciler.reconcile(raw)
        let external = graph.physicalDevices.filter(\.isExternal)

        try XCTSkipIf(external.isEmpty, "No external USB device is attached.")

        for (index, device) in external.enumerated() {
            for candidate in external.dropFirst(index + 1) {
                XCTAssertFalse(
                    USBStorageReconciler.areEquivalent(device, candidate),
                    "The production matcher considered two reconciled devices equivalent."
                )
            }
        }
        for device in external {
            let breadcrumb = USBTopologyNormalizer.presentationPath(for: device).breadcrumb
            XCTAssertFalse(breadcrumb.contains("Mac → Mac"))
            for volume in device.disks.flatMap(\.partitions).flatMap(\.volumes) where volume.isMounted {
                XCTAssertFalse(volume.mountPath.isEmpty)
                XCTAssertFalse(volume.bsdName.isEmpty)
            }
        }
    }
}
