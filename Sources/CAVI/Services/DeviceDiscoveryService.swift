import Foundation
import AppKit
import DiskArbitration
import IOKit
import IOKit.usb
import CAVICore

/// Discovers external USB/Thunderbolt storage devices using DiskArbitration and IOKit.
/// Monitors hot-plug events and automatically updates the device list on the MainActor.
@Observable
@MainActor
public final class DeviceDiscoveryService {
    public var devices: [DriveDevice] = []
    public var selectedDevice: DriveDevice?
    /// The single source of truth for USB identity, storage ownership,
    /// topology, and bandwidth. UI rows are projections of this graph.
    var reconciledGraph = ReconciledUSBStorageGraph(physicalDevices: [], uplinks: [])
    private var vendorCatalog: USBVendorCatalog?
    private weak var eventLog: HardwareEventLog?
    private var sessionStartedAtByBSDName: [String: Date] = [:]
    
    private var daSession: DASession?
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    public init() {}

    func attachVendorCatalog(_ catalog: USBVendorCatalog) {
        vendorCatalog = catalog
    }

    func attachEventLog(_ eventLog: HardwareEventLog) {
        self.eventLog = eventLog
    }
    
    public func startMonitoring() {
        startDiskArbitration()
        startIOKitNotifications()
        refreshDevices()
    }
    
    public func stopMonitoring() {
        if let session = daSession {
            DASessionSetDispatchQueue(session, nil)
            daSession = nil
        }
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        if terminatedIterator != 0 {
            IOObjectRelease(terminatedIterator)
            terminatedIterator = 0
        }
    }
    
    // MARK: - Safe Eject Device
    
    /// Safely unmounts and ejects the specified drive using NSWorkspace.
    public func ejectDevice(_ device: DriveDevice) async throws {
        let url = URL(fileURLWithPath: device.mountPath)
        try await Task.detached(priority: .userInitiated) {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        }.value
        refreshDevices()
    }
    
    // MARK: - Mount Device
    
    public func mountDevice(_ device: DriveDevice) async throws {
        try await mountDevice(device, partitionBSDName: nil)
    }

    public func mountPartition(_ partitionBSDName: String, on device: DriveDevice) async throws {
        try await mountDevice(device, partitionBSDName: partitionBSDName)
    }

    private func mountDevice(_ device: DriveDevice, partitionBSDName: String?) async throws {
        guard let physicalDeviceID = device.physicalDeviceID,
              let physicalDevice = reconciledGraph.physicalDevices.first(where: { $0.id == physicalDeviceID }) else {
            throw NSError(
                domain: "iCollegamenti",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Impossibile montare: il dispositivo riconciliato non è più disponibile."]
            )
        }

        if partitionBSDName == nil, StorageVolumeSelection.benchmarkVolume(for: physicalDevice) != nil {
            return
        }
        guard let target = StorageVolumeSelection.mountTarget(
            for: physicalDevice,
            partitionBSDName: partitionBSDName
        ) else {
            throw NSError(
                domain: "iCollegamenti",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Impossibile montare: nessuna partizione non montata è disponibile per questo dispositivo."]
            )
        }

        do {
            try await DiskArbitrationMountService.mount(partitionBSDName: target.bsdName)
        } catch let diskArbitrationError {
            do {
                try await DiskArbitrationMountService.mountWithDiskutilFallback(partitionBSDName: target.bsdName)
            } catch let fallbackError {
                throw NSError(
                    domain: "iCollegamenti",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Impossibile montare la partizione \(target.bsdName). Disk Arbitration: \(diskArbitrationError.localizedDescription). Fallback diskutil: \(fallbackError.localizedDescription)"]
                )
            }
        }

        // Disk Arbitration can publish the volume shortly after completion.
        try await Task.sleep(for: .milliseconds(350))
        await refreshDevicesNow()
    }
    
    // MARK: - DiskArbitration Monitoring (Dispatched to Main Queue)
    
    private func startDiskArbitration() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.daSession = session
        
        // Dispatch callbacks directly to Main Queue to match @MainActor isolation
        DASessionSetDispatchQueue(session, DispatchQueue.main)
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        DARegisterDiskAppearedCallback(session, nil, { _, ctx in
            guard let ctx = ctx else { return }
            let service = Unmanaged<DeviceDiscoveryService>.fromOpaque(ctx).takeUnretainedValue()
            service.refreshDevices()
        }, context)
        
        DARegisterDiskDisappearedCallback(session, nil, { _, ctx in
            guard let ctx = ctx else { return }
            let service = Unmanaged<DeviceDiscoveryService>.fromOpaque(ctx).takeUnretainedValue()
            service.refreshDevices()
        }, context)
    }
    
    // MARK: - IOKit USB Hot-Plug Notifications (Dispatched to Main Queue)
    
    private func startIOKitNotifications() {
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notificationPort else { return }
        
        // Dispatch notifications directly to Main Queue
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        let addedCallback: IOServiceMatchingCallback = { ctx, iterator in
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                IOObjectRelease(entry)
            }
            guard let ctx = ctx else { return }
            let service = Unmanaged<DeviceDiscoveryService>.fromOpaque(ctx).takeUnretainedValue()
            service.refreshDevices()
        }
        
        let terminatedCallback: IOServiceMatchingCallback = { ctx, iterator in
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                IOObjectRelease(entry)
            }
            guard let ctx = ctx else { return }
            let service = Unmanaged<DeviceDiscoveryService>.fromOpaque(ctx).takeUnretainedValue()
            service.refreshDevices()
        }
        
        let matchAdd = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        IOServiceAddMatchingNotification(port, kIOPublishNotification, matchAdd, addedCallback, context, &addedIterator)
        addedCallback(context, addedIterator) // drain initial
        
        let matchTerm = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matchTerm, terminatedCallback, context, &terminatedIterator)
        terminatedCallback(context, terminatedIterator) // drain initial
    }
    
    // MARK: - Device Scanning
    
    public func refreshDevices() {
        Task {
            await self.refreshDevicesNow()
        }
    }

    private func refreshDevicesNow() async {
        let previousPhysicalDeviceID = selectedDevice?.physicalDeviceID
        let previousBSDName = selectedDevice?.bsdName
        let graph = await Self.scanGraphAsync()
        let foundDevices = graph.physicalDevices.map(Self.makeDriveDevice).map { resolveVendorName(for: $0) }
        reconciledGraph = graph
        updateConnectionSessions(with: foundDevices)
        eventLog?.observe(foundDevices)
        devices = foundDevices
        let candidateByPhysical = previousPhysicalDeviceID.flatMap { id in
            foundDevices.first { $0.physicalDeviceID == id }
        }
        let candidateByBSD = DeviceRefreshPolicy.selectedBSDName(
            previous: previousBSDName,
            available: foundDevices.map(\.bsdName)
        ).flatMap { bsdName in
            foundDevices.first { $0.bsdName == bsdName }
        }
        selectedDevice = candidateByPhysical ?? candidateByBSD ?? foundDevices.first(where: \.isStorageDevice) ?? foundDevices.first
    }

    public func connectionFingerprint(for device: DriveDevice) -> String {
        let startedAt = sessionStartedAtByBSDName[device.bsdName] ?? Date()
        return device.recognitionFingerprint(connectedAt: startedAt)
    }

    func bandwidthBudgets(for device: DriveDevice) -> [ObservedHubBudget] {
        guard let physicalDeviceID = device.physicalDeviceID,
              let physical = reconciledGraph.physicalDevices.first(where: { $0.id == physicalDeviceID }) else {
            return []
        }
        return physical.technicalTopology.compactMap { node in
            guard node.kind == .externalHub,
                  let budget = BandwidthAccounting.budget(forUplinkID: node.id, in: reconciledGraph) else {
                return nil
            }
            return ObservedHubBudget(
                locationID: node.identity?.locationID ?? node.id.hashValue,
                hubName: node.displayName,
                budget: budget
            )
        }
    }

    private func updateConnectionSessions(with devices: [DriveDevice]) {
        let bsdNames = Set(devices.map(\.bsdName).filter { !$0.isEmpty })
        sessionStartedAtByBSDName = sessionStartedAtByBSDName.filter { bsdNames.contains($0.key) }
        let now = Date()
        for bsdName in bsdNames where sessionStartedAtByBSDName[bsdName] == nil {
            sessionStartedAtByBSDName[bsdName] = now
        }
    }

    private func resolveVendorName(for device: DriveDevice) -> DriveDevice {
        let officialVendor = vendorCatalog?.name(for: device.vendorID) ?? device.vendorName
        let officialProduct = vendorCatalog?.productName(for: device.vendorID, productID: device.productID) ?? device.productName
        return DriveDevice(
            id: device.id,
            physicalDeviceID: device.physicalDeviceID,
            topologyBreadcrumb: device.topologyBreadcrumb,
            volumeName: device.volumeName,
            mountPath: device.mountPath,
            bsdName: device.bsdName,
            capacity: device.capacity,
            freeSpace: device.freeSpace,
            vendorID: device.vendorID,
            productID: device.productID,
            serialNumber: device.serialNumber,
            vendorName: officialVendor,
            productName: officialProduct,
            negotiatedSpeedBps: device.negotiatedSpeedBps,
            protocol_: device.protocol_,
            isInternal: device.isInternal,
            fileSystem: device.fileSystem,
            isSolidState: device.isSolidState,
            locationID: device.locationID,
            usbTopology: device.usbTopology,
            powerInfo: device.powerInfo,
            isStorageDevice: device.isStorageDevice,
            isMounted: device.isMounted,
            storageConnectionKind: device.storageConnectionKind,
            connectionSnapshot: device.connectionSnapshot
        )
    }

    private nonisolated static func scanGraphAsync() async -> ReconciledUSBStorageGraph {
        await Task.detached(priority: .userInitiated) {
            USBStorageReconciler.reconcile(MacOSUSBObservationAdapter.collectSynchronously())
        }.value
    }

    private nonisolated static func makeDriveDevice(from physical: USBPhysicalDevice) -> DriveDevice {
        let benchmarkVolume = StorageVolumeSelection.benchmarkVolume(for: physical)
        let mountTarget = StorageVolumeSelection.mountTarget(for: physical)
        let primaryDisk = physical.disks.sorted { $0.bsdName < $1.bsdName }.first
        let primaryBSDName = benchmarkVolume?.bsdName ?? mountTarget?.bsdName ?? primaryDisk?.bsdName ?? ""
        let capacity = benchmarkVolume?.capacityBytes ?? primaryDisk?.capacityBytes ?? 0
        let freeSpace = benchmarkVolume?.freeSpaceBytes ?? 0
        let topology = physical.technicalTopology.map { node in
            USBTopologyNode(
                className: className(for: node.kind),
                productName: node.displayName,
                vendorID: node.identity?.vendorID,
                productID: node.identity?.productID,
                serialNumber: node.identity?.serialNumber,
                linkSpeedBps: node.negotiatedSpeedBps,
                isHub: node.kind == .externalHub,
                locationID: node.identity?.locationID
            )
        }
        let snapshot = ConnectionSnapshot(
            protocolName: "USB",
            negotiatedLinkSpeedBps: physical.negotiatedLinkSpeedBps,
            fileSystem: benchmarkVolume?.fileSystem,
            ioRegistryNodeNames: topology.map(\.className)
        )

        return DriveDevice(
            physicalDeviceID: physical.id,
            topologyBreadcrumb: USBTopologyNormalizer.presentationPath(for: physical).breadcrumb,
            volumeName: benchmarkVolume?.volumeName ?? physical.displayName,
            mountPath: benchmarkVolume?.mountPath ?? "",
            bsdName: primaryBSDName,
            capacity: capacity,
            freeSpace: freeSpace,
            vendorID: physical.identity.vendorID,
            productID: physical.identity.productID,
            serialNumber: physical.identity.serialNumber,
            productName: physical.displayName,
            negotiatedSpeedBps: physical.negotiatedLinkSpeedBps,
            protocol_: "USB",
            isInternal: false,
            fileSystem: benchmarkVolume?.fileSystem,
            isSolidState: physical.disks.isEmpty ? nil : true,
            locationID: physical.identity.locationID,
            usbTopology: topology,
            isStorageDevice: !physical.disks.isEmpty,
            isMounted: benchmarkVolume != nil,
            storageConnectionKind: .usbOrThunderbolt,
            connectionSnapshot: snapshot
        )
    }

    private nonisolated static func className(for kind: RawUSBNodeKind) -> String {
        switch kind {
        case .host: "AppleARMPE"
        case .controller: "AppleUSBXHCI"
        case .rootHub: "IOUSBRootHub"
        case .externalHub, .bridge, .physicalDevice: "IOUSBHostDevice"
        }
    }
    
    private nonisolated func scanDevicesAsync() async -> [DriveDevice] {
        return await Task.detached(priority: .userInitiated) {
            guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
            
            var result: [DriveDevice] = []
            var seenBSD = Set<String>()
            
            let resourceKeys: [URLResourceKey] = [
                .volumeNameKey, .volumeIsInternalKey, .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey, .volumeIsReadOnlyKey
            ]
            
            // 1. Scan all IOMedia objects to detect BOTH mounted and unmounted external USB/TB storage drives
            let mediaMatching = IOServiceMatching("IOMedia")
            var mediaIterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, mediaMatching, &mediaIterator) == KERN_SUCCESS {
                defer { IOObjectRelease(mediaIterator) }
                var mediaService = IOIteratorNext(mediaIterator)
                while mediaService != 0 {
                    let currentMediaService = mediaService
                    defer { IOObjectRelease(currentMediaService) }
                    
                    if let disk = DADiskCreateFromIOMedia(kCFAllocatorDefault, session, currentMediaService),
                       let desc = DADiskCopyDescription(disk) as? [String: Any] {
                        
                        let isInternal = desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? true
                        let protocolName = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
                        let isRemovable = desc[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
                        if let storageConnectionKind = StorageDiscoveryPolicy.connectionKind(
                            isInternal: isInternal,
                            isRemovable: isRemovable,
                            protocolName: protocolName
                        ) {
                        
                        let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String ?? ""
                            
                        if !bsdName.isEmpty && !seenBSD.contains(bsdName) {
                            seenBSD.insert(bsdName)
                                
                                let model = (desc[kDADiskDescriptionDeviceModelKey as String] as? String ?? "").trimmingCharacters(in: .whitespaces)
                                let fileSystem = desc[kDADiskDescriptionVolumeKindKey as String] as? String
                                let volumeURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL
                                
                                let isMounted = (volumeURL != nil)
                                var mountPath = ""
                                var volumeName = ""
                                var capacity: UInt64 = 0
                                var freeSpace: UInt64 = 0
                                
                                if let url = volumeURL {
                                    mountPath = url.path
                                    let resourceValues = try? url.resourceValues(forKeys: Set(resourceKeys))
                                    volumeName = resourceValues?.volumeName ?? url.lastPathComponent
                                    capacity = UInt64(resourceValues?.volumeTotalCapacity ?? 0)
                                    freeSpace = UInt64(resourceValues?.volumeAvailableCapacity ?? 0)
                                } else {
                                    capacity = (desc[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.uint64Value ?? 0
                                    let rawVolName = desc[kDADiskDescriptionVolumeNameKey as String] as? String
                                    let mediaName = desc[kDADiskDescriptionMediaNameKey as String] as? String
                                    volumeName = rawVolName ?? mediaName ?? bsdName
                                }
                                
                                let topology = USBTopologyService.getTopology(forIOMediaService: currentMediaService)
                                let usbProps = DeviceDiscoveryService.extractUSBPropertiesStatic(from: currentMediaService)
                                let blockSizeBytes = (desc[kDADiskDescriptionMediaBlockSizeKey as String] as? NSNumber)?.uint64Value
                                let snapshot = ConnectionSnapshot(
                                    protocolName: protocolName.isEmpty ? nil : protocolName,
                                    negotiatedLinkSpeedBps: usbProps?.linkSpeedBps,
                                    fileSystem: fileSystem,
                                    blockSizeBytes: blockSizeBytes,
                                    bridge: BridgeCatalog.match(vendorID: usbProps?.vendorID, productID: usbProps?.productID),
                                    ioRegistryNodeNames: topology.map(\.className),
                                    technicalProperties: usbProps?.technicalProperties ?? []
                                )
                                
                            let device = DriveDevice(
                                    volumeName: volumeName,
                                    mountPath: mountPath,
                                    bsdName: bsdName,
                                    capacity: capacity,
                                    freeSpace: freeSpace,
                                    vendorID: usbProps?.vendorID,
                                    productID: usbProps?.productID,
                                    serialNumber: usbProps?.serialNumber,
                                    vendorName: usbProps?.vendorName,
                                    productName: usbProps?.productName ?? (model.isEmpty ? "Disco USB" : model),
                                    negotiatedSpeedBps: usbProps?.linkSpeedBps,
                                    protocol_: protocolName,
                                    isInternal: isInternal,
                                    fileSystem: fileSystem,
                                    isSolidState: true,
                                    locationID: usbProps?.locationID != nil ? Int(usbProps!.locationID!) : nil,
                                    usbTopology: topology,
                                    powerInfo: usbProps?.powerInfo,
                                    isStorageDevice: true,
                                    isMounted: isMounted,
                                    storageConnectionKind: storageConnectionKind,
                                    connectionSnapshot: snapshot
                            )
                            result.append(device)
                        }
                        }
                    }
                    mediaService = IOIteratorNext(mediaIterator)
                }
            }
            
            // 2. Scan all non-storage USB peripherals
            let matching = IOServiceMatching("IOUSBHostDevice")
            var iterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS {
                defer { IOObjectRelease(iterator) }
                var service = IOIteratorNext(iterator)
                while service != 0 {
                    let currentService = service
                    defer { IOObjectRelease(currentService) }
                    var props: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(currentService, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                       let dict = props?.takeRetainedValue() as? [String: Any] {
                        let deviceClass = dict["bDeviceClass"] as? Int ?? 0
                        if deviceClass != 9 { // Not a hub
                            let vendorID = dict["idVendor"] as? Int
                            let productID = dict["idProduct"] as? Int
                            let serialNumber = dict["USB Serial Number"] as? String ?? dict["kUSBSerialNumberString"] as? String
                            let locationID = dict["locationID"] as? Int
                            
                            // Check if this USB device is already associated with a storage drive (mounted or unmounted)
                            let alreadyAdded = result.contains { drive in
                                let directMatch = drive.vendorID == vendorID && drive.productID == productID &&
                                    (drive.locationID == locationID || (drive.serialNumber != nil && drive.serialNumber == serialNumber))
                                let topologyMatch = drive.isStorageDevice && USBAssociationPolicy.matches(
                                    locationID: locationID,
                                    vendorID: vendorID,
                                    productID: productID,
                                    topology: drive.usbTopology.map { USBIdentity(locationID: $0.locationID, vendorID: $0.vendorID, productID: $0.productID) }
                                )
                                return directMatch || topologyMatch
                            }
                            
                            if !alreadyAdded {
                                let vendorName = dict["USB Vendor Name"] as? String ?? dict["kUSBVendorString"] as? String
                                let productName = dict["USB Product Name"] as? String ?? dict["kUSBProductString"] as? String ?? "Periferica USB"
                                let linkSpeed = dict["UsbLinkSpeed"] as? UInt64
                                var powerInfo: PowerInfo?
                                if let powerSink = dict["UsbPowerSinkAllocation"] as? Int {
                                    powerInfo = PowerInfo(powerSinkAllocationMw: powerSink)
                                }
                                let topology = USBTopologyService.getTopology(forIOMediaService: currentService)
                                let snapshot = ConnectionSnapshot(
                                    protocolName: "USB",
                                    negotiatedLinkSpeedBps: linkSpeed,
                                    bridge: BridgeCatalog.match(vendorID: vendorID, productID: productID),
                                    ioRegistryNodeNames: topology.map(\.className),
                                    technicalProperties: DeviceDiscoveryService.technicalProperties(from: dict)
                                )
                                
                                let peripheralDevice = DriveDevice(
                                    volumeName: "",
                                    mountPath: "",
                                    bsdName: "",
                                    capacity: 0,
                                    freeSpace: 0,
                                    vendorID: vendorID,
                                    productID: productID,
                                    serialNumber: serialNumber,
                                    vendorName: vendorName,
                                    productName: productName,
                                    negotiatedSpeedBps: linkSpeed,
                                    protocol_: "USB",
                                    isInternal: false,
                                    fileSystem: nil,
                                    isSolidState: nil,
                                    locationID: locationID,
                                    usbTopology: topology,
                                    powerInfo: powerInfo,
                                    isStorageDevice: false,
                                    isMounted: false,
                                    storageConnectionKind: .usbOrThunderbolt,
                                    connectionSnapshot: snapshot
                                )
                                result.append(peripheralDevice)
                            }
                        }
                    }
                    service = IOIteratorNext(iterator)
                }
            }
            
            return result
        }.value
    }
    
    // MARK: - Static IORegistry Property Extraction
    
    private struct USBPropertiesResult: Sendable {
        var vendorName: String?
        var productName: String?
        var serialNumber: String?
        var vendorID: Int?
        var productID: Int?
        var linkSpeedBps: UInt64?
        var locationID: UInt32?
        var powerInfo: PowerInfo?
        var technicalProperties: [TechnicalProperty] = []
    }
    
    private static nonisolated func extractUSBPropertiesStatic(from ioMedia: io_service_t) -> USBPropertiesResult? {
        var current: io_service_t = ioMedia
        IOObjectRetain(current)
        
        while current != 0 {
            var classNameBuf = [CChar](repeating: 0, count: 256)
            IOObjectGetClass(current, &classNameBuf)
            let className = classNameBuf.withUnsafeBufferPointer { buf in
                String(cString: buf.baseAddress!)
            }
            
            if className == "IOUSBHostDevice" {
                var props: Unmanaged<CFMutableDictionary>?
                let kr = IORegistryEntryCreateCFProperties(current, &props, kCFAllocatorDefault, 0)
                if kr == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] {
                    let deviceClass = dict["bDeviceClass"] as? Int ?? 0
                    if deviceClass != 9 { // Not a hub
                        var result = USBPropertiesResult()
                        result.vendorName = dict["USB Vendor Name"] as? String ?? dict["kUSBVendorString"] as? String
                        result.productName = dict["USB Product Name"] as? String ?? dict["kUSBProductString"] as? String
                        result.serialNumber = dict["USB Serial Number"] as? String ?? dict["kUSBSerialNumberString"] as? String
                        result.vendorID = dict["idVendor"] as? Int
                        result.productID = dict["idProduct"] as? Int
                        result.linkSpeedBps = dict["UsbLinkSpeed"] as? UInt64
                        result.locationID = dict["locationID"] as? UInt32
                        
                        if let powerSink = dict["UsbPowerSinkAllocation"] as? Int {
                            result.powerInfo = PowerInfo(powerSinkAllocationMw: powerSink)
                        }
                        result.technicalProperties = technicalProperties(from: dict)
                        
                        IOObjectRelease(current)
                        return result
                    }
                }
            }
            
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr != KERN_SUCCESS { break }
            current = parent
        }
        
        return nil
    }

    private static nonisolated func technicalProperties(from dictionary: [String: Any]) -> [TechnicalProperty] {
        var properties: [TechnicalProperty] = []

        if let speed = dictionary["UsbLinkSpeed"] as? UInt64 {
            properties.append(TechnicalProperty(key: "UsbLinkSpeed", value: TransferSpeedFormatter.linkSpeed(speed)))
        }
        if let specification = dictionary["USB Spec"] {
            properties.append(TechnicalProperty(key: "USB Spec", value: String(describing: specification)))
        }
        if let deviceClass = dictionary["bDeviceClass"] {
            properties.append(TechnicalProperty(key: "bDeviceClass", value: String(describing: deviceClass)))
        }
        if let locationID = dictionary["locationID"] as? Int {
            properties.append(TechnicalProperty(key: "locationID", value: String(format: "0x%08X", locationID)))
        }
        if let powerSink = dictionary["UsbPowerSinkAllocation"] as? Int {
            properties.append(TechnicalProperty(key: "UsbPowerSinkAllocation", value: "\(powerSink) mW"))
        }

        return properties.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }
}
