import CAVICore

enum USBStorageFixtures {
    static let fiveGigabits: UInt64 = 5_000_000_000

    static func mountedSanDiskObservedThroughTwoLayers() -> RawUSBStorageObservationSet {
        let nodes = standardPath(
            deviceID: "sandisk-usb-endpoint",
            locationID: 0x0024_0000,
            registryEntryID: 0x1000_2400,
            registryPath: "IOService:/AppleARMPE/usb@0/HS01@00240000",
            serialNumber: "MOCK-SERIAL-0001",
            productName: "SanDisk 3.2Gen1"
        )

        return RawUSBStorageObservationSet(
            registryNodes: nodes,
            media: [
                RawStorageMediaObservation(
                    bsdName: "disk4",
                    parentBSDName: nil,
                    kind: .wholeDisk,
                    registryEntryID: 0x2000_0400,
                    registryAncestorEntryID: 0x1000_2400,
                    registryAncestorPath: "IOService:/AppleARMPE/usb@0/HS01@00240000",
                    mediaUUID: "D4A1-0000-0000-0000",
                    volumeUUID: nil,
                    fileSystem: nil,
                    volumeName: "SanDisk USB",
                    mountPath: nil,
                    capacityBytes: 64_000_000_000,
                    freeSpaceBytes: nil,
                    isReadOnly: false
                ),
                RawStorageMediaObservation(
                    bsdName: "disk4s1",
                    parentBSDName: "disk4",
                    kind: .partition,
                    registryEntryID: 0x2000_0401,
                    registryAncestorEntryID: 0x1000_2400,
                    registryAncestorPath: "IOService:/AppleARMPE/usb@0/HS01@00240000",
                    mediaUUID: "D4A1-0000-0000-0001",
                    volumeUUID: "B4A1-0000-0000-0001",
                    fileSystem: "msdos",
                    volumeName: "SANDISK",
                    mountPath: "/Volumes/SANDISK",
                    capacityBytes: 63_900_000_000,
                    freeSpaceBytes: 42_000_000_000,
                    isReadOnly: false
                )
            ]
        )
    }

    /// Disk Arbitration and IOKit can both surface the same whole IOMedia
    /// during one refresh. The second record intentionally has less metadata,
    /// as can happen while the volume description is still being populated.
    static func mountedSanDiskWithDuplicateWholeDiskObservation() -> RawUSBStorageObservationSet {
        var fixture = mountedSanDiskObservedThroughTwoLayers()
        fixture.media.append(RawStorageMediaObservation(
            bsdName: "disk4",
            parentBSDName: nil,
            kind: .wholeDisk,
            registryEntryID: 0x2000_0400,
            registryAncestorEntryID: 0x1000_2400,
            registryAncestorPath: "IOService:/AppleARMPE/usb@0/HS01@00240000",
            mediaUUID: nil,
            volumeUUID: nil,
            fileSystem: nil,
            volumeName: nil,
            mountPath: nil,
            capacityBytes: nil,
            freeSpaceBytes: nil,
            isReadOnly: false
        ))
        return fixture
    }

    static func serialLessDriveObservedThroughTwoLayers() -> RawUSBStorageObservationSet {
        let registryPath = "IOService:/AppleARMPE/usb@0/HS02@00310000"
        return RawUSBStorageObservationSet(
            registryNodes: standardPath(
                deviceID: "serial-less-endpoint",
                locationID: 0x0031_0000,
                registryEntryID: 0x1000_3100,
                registryPath: registryPath,
                serialNumber: nil,
                productName: "USB Mass Storage"
            ),
            media: [RawStorageMediaObservation(
                bsdName: "disk5",
                parentBSDName: nil,
                kind: .wholeDisk,
                registryEntryID: 0x2000_0500,
                registryAncestorEntryID: nil,
                registryAncestorPath: registryPath,
                mediaUUID: "D5A1",
                volumeUUID: nil,
                fileSystem: nil,
                volumeName: "USB Mass Storage",
                mountPath: nil,
                capacityBytes: 32_000_000_000,
                freeSpaceBytes: nil,
                isReadOnly: false
            )]
        )
    }

    static func identicalVIDPIDAtDifferentLocations() -> RawUSBStorageObservationSet {
        RawUSBStorageObservationSet(
            registryNodes: standardPath(
                deviceID: "first-identical-drive",
                locationID: 0x0041_0000,
                registryEntryID: 0x1000_4100,
                registryPath: "IOService:/AppleARMPE/usb@0/HS03@00410000",
                serialNumber: nil,
                productName: "Twin Drive"
            ) + standardPath(
                deviceID: "second-identical-drive",
                locationID: 0x0042_0000,
                registryEntryID: 0x1000_4200,
                registryPath: "IOService:/AppleARMPE/usb@0/HS04@00420000",
                serialNumber: nil,
                productName: "Twin Drive"
            ),
            media: []
        )
    }

    static func sameSerialAtConflictingLocations() -> RawUSBStorageObservationSet {
        RawUSBStorageObservationSet(
            registryNodes: standardPath(
                deviceID: "stale-location-one",
                locationID: 0x0043_0000,
                registryEntryID: nil,
                registryPath: "IOService:/AppleARMPE/usb@0/HS03@00430000",
                serialNumber: "ABC",
                productName: "Conflicting Location Drive"
            ) + standardPath(
                deviceID: "stale-location-two",
                locationID: 0x0044_0000,
                registryEntryID: nil,
                registryPath: "IOService:/AppleARMPE/usb@0/HS04@00440000",
                serialNumber: "ABC",
                productName: "Conflicting Location Drive"
            ),
            media: []
        )
    }

    static func driveWithTwoMountedPartitions() -> RawUSBStorageObservationSet {
        var fixture = mountedSanDiskObservedThroughTwoLayers()
        fixture.media.append(RawStorageMediaObservation(
            bsdName: "disk4s2",
            parentBSDName: "disk4",
            kind: .partition,
            registryEntryID: 0x2000_0402,
            registryAncestorEntryID: 0x1000_2400,
            registryAncestorPath: "IOService:/AppleARMPE/usb@0/HS01@00240000",
            mediaUUID: "D4A1-0000-0000-0002",
            volumeUUID: "B4A1-0000-0000-0002",
            fileSystem: "exfat",
            volumeName: "SECOND",
            mountPath: "/Volumes/SECOND",
            capacityBytes: 20_000_000_000,
            freeSpaceBytes: 10_000_000_000,
            isReadOnly: false
        ))
        return fixture
    }

    static func driveWithOneMountedAndOneUnmountedPartition() -> RawUSBStorageObservationSet {
        var fixture = mountedSanDiskObservedThroughTwoLayers()
        fixture.media.append(RawStorageMediaObservation(
            bsdName: "disk4s2",
            parentBSDName: "disk4",
            kind: .partition,
            registryEntryID: 0x2000_0402,
            registryAncestorEntryID: 0x1000_2400,
            registryAncestorPath: "IOService:/AppleARMPE/usb@0/HS01@00240000",
            mediaUUID: "D4A1-0000-0000-0002",
            volumeUUID: nil,
            fileSystem: "exfat",
            volumeName: "UNMOUNTED_SECOND",
            mountPath: nil,
            capacityBytes: 20_000_000_000,
            freeSpaceBytes: nil,
            isReadOnly: false
        ))
        return fixture
    }

    static func usbNVMeEnclosure() -> RawUSBStorageObservationSet {
        let path = "IOService:/AppleARMPE/usb@0/HS05@00500000"
        return RawUSBStorageObservationSet(
            registryNodes: standardPath(
                deviceID: "nvme-enclosure",
                locationID: 0x0050_0000,
                registryEntryID: 0x1000_5000,
                registryPath: path,
                serialNumber: "ENCLOSURE-0001",
                productName: "USB NVMe Enclosure",
                bridge: true
            ),
            media: [RawStorageMediaObservation(
                bsdName: "disk8",
                parentBSDName: nil,
                kind: .wholeDisk,
                registryEntryID: 0x2000_0800,
                registryAncestorEntryID: 0x1000_5000,
                registryAncestorPath: path,
                mediaUUID: "D8A1",
                volumeUUID: nil,
                fileSystem: nil,
                volumeName: "NVMe",
                mountPath: nil,
                capacityBytes: 1_000_000_000_000,
                freeSpaceBytes: nil,
                isReadOnly: false
            )]
        )
    }

    static func unmountedPartitionedDrive() -> RawUSBStorageObservationSet {
        let path = "IOService:/AppleARMPE/usb@0/HS06@00600000"
        return RawUSBStorageObservationSet(
            registryNodes: standardPath(
                deviceID: "unmounted-drive",
                locationID: 0x0060_0000,
                registryEntryID: 0x1000_6000,
                registryPath: path,
                serialNumber: "UNMOUNTED-1",
                productName: "Unmounted Drive"
            ),
            media: [
                RawStorageMediaObservation(
                    bsdName: "disk6",
                    parentBSDName: nil,
                    kind: .wholeDisk,
                    registryEntryID: 0x2000_0600,
                    registryAncestorEntryID: 0x1000_6000,
                    registryAncestorPath: path,
                    mediaUUID: "D6A1",
                    volumeUUID: nil,
                    fileSystem: nil,
                    volumeName: "Unmounted Drive",
                    mountPath: nil,
                    capacityBytes: 64_000_000_000,
                    freeSpaceBytes: nil,
                    isReadOnly: false
                ),
                RawStorageMediaObservation(
                    bsdName: "disk6s1",
                    parentBSDName: "disk6",
                    kind: .partition,
                    registryEntryID: 0x2000_0601,
                    registryAncestorEntryID: 0x1000_6000,
                    registryAncestorPath: path,
                    mediaUUID: "D6A2",
                    volumeUUID: nil,
                    fileSystem: "exfat",
                    volumeName: "UNMOUNTED",
                    mountPath: nil,
                    capacityBytes: 63_000_000_000,
                    freeSpaceBytes: nil,
                    isReadOnly: false
                )
            ]
        )
    }

    static func threeDevicesOnFiveGigabitHub() -> RawUSBStorageObservationSet {
        let hub = RawUSBRegistryNode(
            id: "hub-external-1",
            parentID: "root-hub-1",
            kind: .externalHub,
            identity: RawUSBIdentity(
                vendorID: 0x2109,
                productID: 0x0817,
                serialNumber: "HUB-0001",
                locationID: 0x0020_0000,
                registryEntryID: 0x1000_2000,
                registryPath: "IOService:/AppleARMPE/usb@0/HS00@00200000"
            ),
            displayName: "USB 3.0 Hub",
            negotiatedSpeedBps: fiveGigabits
        )
        let host = RawUSBRegistryNode.host(id: "host-1")
        let controller = RawUSBRegistryNode.controller(id: "controller-1", parentID: host.id)
        let rootHub = RawUSBRegistryNode.rootHub(id: "root-hub-1", parentID: controller.id)
        let drives = (1...3).map { index in
            RawUSBRegistryNode(
                id: "shared-hub-drive-\(index)",
                parentID: hub.id,
                kind: .physicalDevice,
                identity: RawUSBIdentity(
                    vendorID: 0x0781,
                    productID: 0x5595,
                    serialNumber: "SANDISK-\(index)",
                    locationID: 0x0024_0000 + index,
                    registryEntryID: 0x1000_2400 + UInt64(index),
                    registryPath: "IOService:/AppleARMPE/usb@0/HS0\(index)"
                ),
                displayName: "SanDisk \(index)",
                negotiatedSpeedBps: fiveGigabits
            )
        }
        return RawUSBStorageObservationSet(registryNodes: [host, controller, rootHub, hub] + drives, media: [])
    }

    static func nestedHubsWithTwoFiveGigabitDrives() -> RawUSBStorageObservationSet {
        let host = RawUSBRegistryNode.host(id: "host-1")
        let controller = RawUSBRegistryNode.controller(id: "controller-1", parentID: host.id)
        let rootHub = RawUSBRegistryNode.rootHub(id: "root-hub-1", parentID: controller.id)
        let hubA = RawUSBRegistryNode(
            id: "hub-a-10g",
            parentID: rootHub.id,
            kind: .externalHub,
            identity: RawUSBIdentity(
                vendorID: 0x2109, productID: 0x2817, serialNumber: "HUB-A",
                locationID: 0x0020_0000, registryEntryID: 0x1000_2000,
                registryPath: "IOService:/AppleARMPE/usb@0/HS00@00200000"
            ),
            displayName: "Hub A",
            negotiatedSpeedBps: 10_000_000_000
        )
        let hubB = RawUSBRegistryNode(
            id: "hub-b-5g",
            parentID: hubA.id,
            kind: .externalHub,
            identity: RawUSBIdentity(
                vendorID: 0x2109, productID: 0x0817, serialNumber: "HUB-B",
                locationID: 0x0021_0000, registryEntryID: 0x1000_2100,
                registryPath: "IOService:/AppleARMPE/usb@0/HS00@00210000"
            ),
            displayName: "Hub B",
            negotiatedSpeedBps: fiveGigabits
        )
        let drives = (1...2).map { index in
            RawUSBRegistryNode(
                id: "nested-drive-\(index)",
                parentID: hubB.id,
                kind: .physicalDevice,
                identity: RawUSBIdentity(
                    vendorID: 0x0781, productID: 0x5595, serialNumber: "NESTED-\(index)",
                    locationID: 0x0022_0000 + index, registryEntryID: 0x1000_2200 + UInt64(index),
                    registryPath: "IOService:/AppleARMPE/usb@0/HS00@0022\(index)000"
                ),
                displayName: "Nested Drive \(index)",
                negotiatedSpeedBps: fiveGigabits
            )
        }
        return RawUSBStorageObservationSet(
            registryNodes: [host, controller, rootHub, hubA, hubB] + drives,
            media: []
        )
    }

    private static func standardPath(
        deviceID: String,
        locationID: Int,
        registryEntryID: UInt64?,
        registryPath: String,
        serialNumber: String?,
        productName: String,
        bridge: Bool = false
    ) -> [RawUSBRegistryNode] {
        let host = RawUSBRegistryNode.host(id: "host-1")
        let controller = RawUSBRegistryNode.controller(id: "controller-1", parentID: host.id)
        let rootHub = RawUSBRegistryNode.rootHub(id: "root-hub-1", parentID: controller.id)
        let hub = RawUSBRegistryNode(
            id: "hub-external-1",
            parentID: rootHub.id,
            kind: .externalHub,
            identity: RawUSBIdentity(
                vendorID: 0x2109,
                productID: 0x0817,
                serialNumber: "HUB-0001",
                locationID: 0x0020_0000,
                registryEntryID: 0x1000_2000,
                registryPath: "IOService:/AppleARMPE/usb@0/HS00@00200000"
            ),
            displayName: "USB 3.0 Hub",
            negotiatedSpeedBps: fiveGigabits
        )
        let endpoint = RawUSBRegistryNode(
            id: deviceID,
            parentID: hub.id,
            kind: bridge ? .bridge : .physicalDevice,
            identity: RawUSBIdentity(
                vendorID: 0x0781,
                productID: 0x5595,
                serialNumber: serialNumber,
                locationID: locationID,
                registryEntryID: registryEntryID,
                registryPath: registryPath
            ),
            displayName: productName,
            negotiatedSpeedBps: fiveGigabits
        )
        return [host, controller, rootHub, hub, endpoint]
    }
}
