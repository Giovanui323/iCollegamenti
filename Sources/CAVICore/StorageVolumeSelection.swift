import Foundation

public enum StorageVolumeSelection {
    public static func benchmarkVolume(for device: USBPhysicalDevice) -> MountedVolume? {
        volumes(for: device)
            .first { $0.isMounted && !$0.isReadOnly }
    }

    public static func mountTarget(
        for device: USBPhysicalDevice,
        partitionBSDName: String? = nil
    ) -> StoragePartition? {
        let partitions = device.disks
            .sorted { $0.bsdName < $1.bsdName }
            .flatMap(\.partitions)
            .sorted { $0.bsdName < $1.bsdName }
        if let partitionBSDName {
            guard let partition = partitions.first(where: { $0.bsdName == partitionBSDName }) else { return nil }
            return partition.volumes.isEmpty ? partition : nil
        }
        return partitions.first(where: { $0.volumes.isEmpty })
    }

    private static func volumes(for device: USBPhysicalDevice) -> [MountedVolume] {
        device.disks
            .sorted { $0.bsdName < $1.bsdName }
            .flatMap(\.partitions)
            .sorted { $0.bsdName < $1.bsdName }
            .flatMap(\.volumes)
    }
}
