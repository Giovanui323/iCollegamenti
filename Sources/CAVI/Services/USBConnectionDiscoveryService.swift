import Foundation
import CAVICore

@Observable
@MainActor
final class USBConnectionDiscoveryService {
    /// Stateless projection. The UI reads it from `DeviceDiscoveryService`'s
    /// observable reconciled graph, so it cannot remain stale after a refresh.
    nonisolated static func snapshots(in graph: ReconciledUSBStorageGraph) -> [USBConnectionSnapshot] {
        graph.physicalDevices.map { device in
            let benchmarkVolume = StorageVolumeSelection.benchmarkVolume(for: device)
            let mountTarget = StorageVolumeSelection.mountTarget(for: device)
            let bsdName = benchmarkVolume?.bsdName ?? mountTarget?.bsdName
            return USBConnectionSnapshot(
                id: device.id,
                displayName: device.displayName,
                vendorID: device.identity.vendorID,
                productID: device.identity.productID,
                serialNumber: device.identity.serialNumber,
                locationID: device.identity.locationID,
                linkSpeedBps: device.negotiatedLinkSpeedBps,
                mountedVolumeBSDName: benchmarkVolume?.bsdName,
                bsdName: bsdName,
                isMounted: benchmarkVolume != nil,
                isStorageDevice: !device.disks.isEmpty,
                mountPath: benchmarkVolume?.mountPath
            )
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
