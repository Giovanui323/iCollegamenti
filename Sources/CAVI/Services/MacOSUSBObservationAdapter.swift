import DiskArbitration
import Foundation
import IOKit
import IOKit.usb
import CAVICore

/// Platform boundary for USB/storage discovery. It preserves IOKit and Disk
/// Arbitration facts; identity decisions belong exclusively to CAVICore.
final class MacOSUSBObservationAdapter {
    func collect() async -> RawUSBStorageObservationSet {
        Self.collectSynchronously()
    }

    nonisolated static func collectSynchronously() -> RawUSBStorageObservationSet {
        var registryNodes: [RawUSBRegistryNode] = []
        var media: [RawStorageMediaObservation] = []

        if let session = DASessionCreate(kCFAllocatorDefault) {
            collectMedia(session: session, registryNodes: &registryNodes, media: &media)
        }
        collectUSBEndpoints(into: &registryNodes)

        return RawUSBStorageObservationSet(registryNodes: registryNodes, media: media)
    }

    private nonisolated static func collectMedia(
        session: DASession,
        registryNodes: inout [RawUSBRegistryNode],
        media: inout [RawStorageMediaObservation]
    ) {
        let matching = IOServiceMatching("IOMedia")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let current = service
            defer { IOObjectRelease(current) }

            guard let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, current),
                  let description = DADiskCopyDescription(disk) as? [String: Any],
                  let bsdName = description[kDADiskDescriptionMediaBSDNameKey as String] as? String,
                  !bsdName.isEmpty else {
                service = IOIteratorNext(iterator)
                continue
            }

            let isInternal = boolValue(description[kDADiskDescriptionDeviceInternalKey as String]) ?? true
            let isRemovable = boolValue(description[kDADiskDescriptionMediaRemovableKey as String]) ?? false
            let protocolName = description[kDADiskDescriptionDeviceProtocolKey as String] as? String
            guard StorageDiscoveryPolicy.connectionKind(
                isInternal: isInternal,
                isRemovable: isRemovable,
                protocolName: protocolName
            ) != nil else {
                service = IOIteratorNext(iterator)
                continue
            }

            let pathNodes = usbPathNodes(from: current)
            guard let endpoint = pathNodes.last(where: {
                $0.kind == .physicalDevice || $0.kind == .bridge
            }), let identity = endpoint.identity else {
                service = IOIteratorNext(iterator)
                continue
            }
            registryNodes.append(contentsOf: pathNodes)

            let wholeBSDName = wholeDiskBSDName(for: disk) ?? bsdName
            let volumeURL = description[kDADiskDescriptionVolumePathKey as String] as? URL
            let values = volumeURL.flatMap { try? $0.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsReadOnlyKey]) }
            let capacity = values?.volumeTotalCapacity.map(UInt64.init)
                ?? numberValue(description[kDADiskDescriptionMediaSizeKey as String]).map(UInt64.init)
            let freeSpace = values?.volumeAvailableCapacity.map(UInt64.init)
            let readOnly = values?.volumeIsReadOnly ?? false

            media.append(RawStorageMediaObservation(
                bsdName: bsdName,
                parentBSDName: bsdName == wholeBSDName ? nil : wholeBSDName,
                kind: bsdName == wholeBSDName ? .wholeDisk : .partition,
                registryEntryID: registryEntryID(for: current),
                registryAncestorEntryID: identity.registryEntryID,
                registryAncestorPath: identity.registryPath,
                mediaUUID: description[kDADiskDescriptionMediaUUIDKey as String] as? String,
                volumeUUID: description[kDADiskDescriptionVolumeUUIDKey as String] as? String,
                fileSystem: description[kDADiskDescriptionVolumeKindKey as String] as? String,
                volumeName: description[kDADiskDescriptionVolumeNameKey as String] as? String,
                mountPath: volumeURL?.path,
                capacityBytes: capacity,
                freeSpaceBytes: freeSpace,
                isReadOnly: readOnly
            ))

            service = IOIteratorNext(iterator)
        }
    }

    private nonisolated static func collectUSBEndpoints(into registryNodes: inout [RawUSBRegistryNode]) {
        let matching = IOServiceMatching("IOUSBHostDevice")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let current = service
            defer { IOObjectRelease(current) }
            let properties = properties(for: current)
            let deviceClass = numberValue(properties?["bDeviceClass"]) ?? 0
            if deviceClass != 9 {
                registryNodes.append(contentsOf: usbPathNodes(from: current))
            }
            service = IOIteratorNext(iterator)
        }
    }

    private nonisolated static func wholeDiskBSDName(for disk: DADisk) -> String? {
        guard let wholeDisk = DADiskCopyWholeDisk(disk),
              let description = DADiskCopyDescription(wholeDisk) as? [String: Any] else {
            return nil
        }
        return description[kDADiskDescriptionMediaBSDNameKey as String] as? String
    }

    private struct PathDraft {
        let id: String
        let preliminaryKind: RawUSBNodeKind
        let identity: RawUSBIdentity?
        let displayName: String
        let negotiatedSpeedBps: UInt64?
    }

    private nonisolated static func usbPathNodes(from service: io_service_t) -> [RawUSBRegistryNode] {
        var drafts: [PathDraft] = []
        var current = service
        IOObjectRetain(current)

        while current != 0 {
            if let draft = pathDraft(for: current) {
                drafts.append(draft)
            }
            var parent: io_registry_entry_t = 0
            let result = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard result == KERN_SUCCESS else { break }
            current = parent
        }

        var ordered = drafts.reversed().map { draft in
            RawUSBRegistryNode(
                id: draft.id,
                parentID: nil,
                kind: draft.preliminaryKind,
                identity: draft.identity,
                displayName: draft.displayName,
                negotiatedSpeedBps: draft.negotiatedSpeedBps
            )
        }

        for index in ordered.indices {
            if index > 0 {
                ordered[index] = RawUSBRegistryNode(
                    id: ordered[index].id,
                    parentID: ordered[index - 1].id,
                    kind: ordered[index].kind,
                    identity: ordered[index].identity,
                    displayName: ordered[index].displayName,
                    negotiatedSpeedBps: ordered[index].negotiatedSpeedBps
                )
            }
            if ordered[index].kind == .externalHub,
               index > 0,
               ordered[index - 1].kind == .controller {
                ordered[index] = RawUSBRegistryNode(
                    id: ordered[index].id,
                    parentID: ordered[index - 1].id,
                    kind: .rootHub,
                    identity: ordered[index].identity,
                    displayName: ordered[index].displayName,
                    negotiatedSpeedBps: ordered[index].negotiatedSpeedBps
                )
            }
        }

        guard let controllerIndex = ordered.firstIndex(where: { $0.kind == .controller }) else { return ordered }
        let controller = ordered[controllerIndex]
        let host = RawUSBRegistryNode.host(id: "host:\(controller.id)")
        ordered[controllerIndex] = RawUSBRegistryNode(
            id: controller.id,
            parentID: host.id,
            kind: controller.kind,
            identity: controller.identity,
            displayName: controller.displayName,
            negotiatedSpeedBps: controller.negotiatedSpeedBps
        )
        return [host] + ordered
    }

    private nonisolated static func pathDraft(for service: io_service_t) -> PathDraft? {
        let className = ioClassName(for: service)
        let values = properties(for: service)
        let deviceClass = numberValue(values?["bDeviceClass"]) ?? 0
        let preliminaryKind: RawUSBNodeKind
        if className.localizedCaseInsensitiveContains("XHCI") {
            preliminaryKind = .controller
        } else if className == "IOUSBHostDevice", deviceClass == 9 {
            preliminaryKind = .externalHub
        } else if className == "IOUSBHostDevice" {
            let name = productName(values) ?? "USB device"
            preliminaryKind = isBridge(values, name: name) ? .bridge : .physicalDevice
        } else {
            return nil
        }

        let entryID = registryEntryID(for: service)
        let identity = preliminaryKind == .controller ? nil : RawUSBIdentity(
            vendorID: numberValue(values?["idVendor"]),
            productID: numberValue(values?["idProduct"]),
            serialNumber: values?["USB Serial Number"] as? String ?? values?["kUSBSerialNumberString"] as? String,
            locationID: numberValue(values?["locationID"]),
            registryEntryID: entryID,
            registryPath: registryPath(for: service)
        )

        return PathDraft(
            id: "registry:\(entryID.map(String.init) ?? className)",
            preliminaryKind: preliminaryKind,
            identity: identity,
            displayName: productName(values) ?? (preliminaryKind == .controller ? "USB Controller" : "USB device"),
            negotiatedSpeedBps: unsignedValue(values?["UsbLinkSpeed"])
        )
    }

    private nonisolated static func properties(for service: io_service_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    private nonisolated static func ioClassName(for service: io_service_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        IOObjectGetClass(service, &buffer)
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return "" }
            return String(cString: base)
        }
    }

    private nonisolated static func registryEntryID(for service: io_service_t) -> UInt64? {
        var entryID: UInt64 = 0
        return IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS ? entryID : nil
    }

    private nonisolated static func registryPath(for service: io_service_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 1_024)
        guard IORegistryEntryGetPath(service, kIOServicePlane, &buffer) == KERN_SUCCESS else { return nil }
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return nil }
            return String(cString: base)
        }
    }

    private nonisolated static func vendorName(_ values: [String: Any]?) -> String? {
        values?["USB Vendor Name"] as? String ?? values?["kUSBVendorString"] as? String ?? values?["Manufacturer"] as? String
    }

    private nonisolated static func productName(_ values: [String: Any]?) -> String? {
        values?["USB Product Name"] as? String ?? values?["kUSBProductString"] as? String
    }

    private nonisolated static func isBridge(_ values: [String: Any]?, name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.contains("bridge") || lowercased.contains("enclosure") ||
            ((values?["USB Vendor Name"] as? String)?.lowercased().contains("bridge") == true)
    }

    private nonisolated static func numberValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    private nonisolated static func unsignedValue(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        return value as? UInt64
    }

    private nonisolated static func boolValue(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        return value as? Bool
    }
}
