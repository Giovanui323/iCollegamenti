import Foundation
import IOKit
import IOKit.usb
import DiskArbitration
import CAVICore

// MARK: - BottleneckInfo

public struct BottleneckInfo: Sendable {
    public let nodeName: String
    public let nodeSpeed: UInt64
    public let deviceSpeed: UInt64
    public let message: String
}

public struct ObservedHubBudget: Sendable, Identifiable {
    public let locationID: Int
    public let hubName: String
    public let budget: BandwidthBudget

    public var id: Int { locationID }

    public init(locationID: Int, hubName: String, budget: BandwidthBudget) {
        self.locationID = locationID
        self.hubName = hubName
        self.budget = budget
    }
}

// MARK: - USBTopologyService

public enum USBTopologyService {

    /// Prefer the breadcrumb emitted by the reconciled graph. The array-only
    /// overload remains for legacy callers and raw diagnostic views.
    public static func topologyDescription(for device: DriveDevice) -> String {
        device.topologyBreadcrumb ?? topologyDescription(for: device.usbTopology)
    }

    /// Converts directly observed hubs in an IORegistry path into constraints
    /// that the diagnosis engine can reason about. It deliberately does not
    /// invent per-port or cable capabilities that macOS did not expose.
    public static func connectionConstraints(for topology: [USBTopologyNode]) -> [ConnectionConstraint] {
        topology.compactMap { node in
            guard let speed = node.linkSpeedBps, speed > 0 else { return nil }
            let kind: ConnectionConstraintKind
            if node.isHub {
                kind = .hub
            } else if node.className.contains("XHCI") || node.className.contains("Bridge") || (node.productName?.lowercased().contains("bridge") == true) {
                kind = .controller
            } else if node.className == "IOUSBHostDevice" {
                kind = .device
            } else {
                kind = .unknown
            }
            return ConnectionConstraint(
                label: node.productName ?? (node.isHub ? "Hub USB" : "Controller/Dispositivo"),
                maximumSpeedBps: speed,
                kind: kind,
                source: .ioRegistryObserved
            )
        }
    }

    /// Estimates potential contention for every observed hub in the selected
    /// path. Devices are grouped only by a common I/O Registry location ID;
    /// the values are negotiated link capacities, not live traffic.
    public static func bandwidthBudgets(for device: DriveDevice, among devices: [DriveDevice]) -> [ObservedHubBudget] {
        device.usbTopology.compactMap { sharedHub -> ObservedHubBudget? in
            guard sharedHub.isHub,
                  let locationID = sharedHub.locationID,
                  let uplinkSpeed = sharedHub.linkSpeedBps,
                  uplinkSpeed > 0 else {
                return nil
            }

            let consumers = devices.compactMap { candidate -> BandwidthConsumer? in
                let usesSameHub = candidate.usbTopology.contains { node in
                    node.isHub && node.locationID == locationID
                }
                guard usesSameHub else { return nil }
                return BandwidthConsumer(
                    id: candidate.id.uuidString,
                    label: candidate.displayName,
                    requestedSpeedBps: candidate.negotiatedSpeedBps
                )
            }

            guard !consumers.isEmpty else { return nil }
            return ObservedHubBudget(
                locationID: locationID,
                hubName: sharedHub.productName ?? "Hub USB",
                budget: BandwidthBudgetCalculator.calculate(
                    uplinkSpeedBps: uplinkSpeed,
                    consumers: consumers
                )
            )
        }
    }

    /// Convenience for callers that only need the closest observed hub.
    public static func bandwidthBudget(for device: DriveDevice, among devices: [DriveDevice]) -> BandwidthBudget? {
        bandwidthBudgets(for: device, among: devices).first?.budget
    }
    
    public static func portRecommendations(for devices: [DriveDevice]) -> [PortRecommendation] {
        var recommendations: [PortRecommendation] = []
        var controllerMap: [Int: [DriveDevice]] = [:]
        
        for device in devices {
            if let root = device.usbTopology.last(where: { $0.className.contains("XHCI") }) {
                let locationID = root.locationID ?? 0
                controllerMap[locationID, default: []].append(device)
            }
        }
        
        for (_, group) in controllerMap {
            let highBandwidth = group.filter { ($0.negotiatedSpeedBps ?? 0) >= 5_000_000_000 }
            if highBandwidth.count > 1 {
                for i in 1..<highBandwidth.count {
                    let dev = highBandwidth[i]
                    recommendations.append(PortRecommendation(
                        deviceName: dev.displayName,
                        suggestion: "Move to a different port",
                        reason: "Shares a controller with other high-bandwidth devices."
                    ))
                }
            }
        }
        return recommendations
    }
    
    /// Walks the IORegistry tree from an IOMedia service up to the root USB controller.
    /// Returns an array of USBTopologyNode ordered from the device (index 0) to the controller (last).
    public static func getTopology(forIOMediaService service: io_service_t) -> [USBTopologyNode] {
        var nodes: [USBTopologyNode] = []
        var current: io_service_t = service
        IOObjectRetain(current)
        
        while current != 0 {
            var classNameBuf = [CChar](repeating: 0, count: 256)
            IOObjectGetClass(current, &classNameBuf)
            let className = classNameBuf.withUnsafeBufferPointer { buf in
                String(cString: buf.baseAddress!)
            }
            
            var vendor: String?
            var product: String?
            var vendorID: Int?
            var productID: Int?
            var serial: String?
            var linkSpeed: UInt64?
            var isHub = false
            var locationID: Int?
            
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(current, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                
                vendor = dict["USB Vendor Name"] as? String ?? dict["kUSBVendorString"] as? String
                product = dict["USB Product Name"] as? String ?? dict["kUSBProductString"] as? String
                vendorID = dict["idVendor"] as? Int
                productID = dict["idProduct"] as? Int
                serial = dict["USB Serial Number"] as? String ?? dict["kUSBSerialNumberString"] as? String
                linkSpeed = dict["UsbLinkSpeed"] as? UInt64
                locationID = dict["locationID"] as? Int
                
                if let bDeviceClass = dict["bDeviceClass"] as? Int {
                    isHub = (bDeviceClass == 9)
                }
            }
            
            // Keep physical endpoints only. Generic IOKit driver layers inherit USB properties
            // and would otherwise appear as duplicate devices in the visual chain.
            if className == "IOUSBHostDevice" || className.contains("XHCI") {
                let node = USBTopologyNode(
                    className: className,
                    vendorName: vendor,
                    productName: product,
                    vendorID: vendorID,
                    productID: productID,
                    serialNumber: serial,
                    linkSpeedBps: linkSpeed,
                    isHub: isHub,
                    locationID: locationID
                )
                nodes.append(node)
            }
            
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr != KERN_SUCCESS { break }
            current = parent
        }
        
        return nodes
    }
    
    /// Finds a bottleneck in the USB topology chain.
    /// A bottleneck exists when a hub in the chain has a lower link speed than the device itself.
    public static func findBottleneck(in topology: [USBTopologyNode]) -> BottleneckInfo? {
        // Find the first non-hub IOUSBHostDevice (the actual device)
        guard let deviceNode = topology.first(where: {
            $0.className == "IOUSBHostDevice" && !$0.isHub
        }), let deviceSpeed = deviceNode.linkSpeedBps else {
            return nil
        }
        
        // Check if any hub in the chain is slower than the device
        for node in topology where node.isHub {
            if let hubSpeed = node.linkSpeedBps, hubSpeed < deviceSpeed {
                let name = node.productName ?? "Hub USB"
                let formattedSpeed = LinkSpeedService.formatSpeed(hubSpeed)
                return BottleneckInfo(
                    nodeName: name,
                    nodeSpeed: hubSpeed,
                    deviceSpeed: deviceSpeed,
                    message: "⚠️ COLLO DI BOTTIGLIA: \(name) limitato a \(formattedSpeed)"
                )
            }
        }
        
        return nil
    }
    
    /// Convenience: get topology from a BSD device name (e.g. "disk7s1")
    public static func getTopologyFromBSDName(_ bsdName: String) -> [USBTopologyNode] {
        guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
        
        let path = "/dev/\(bsdName)"
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, path) else { return [] }
        
        let ioMedia = DADiskCopyIOMedia(disk)
        guard ioMedia != 0 else { return [] }
        defer { IOObjectRelease(ioMedia) }
        
        return getTopology(forIOMediaService: ioMedia)
    }
    
    /// Generates a human-readable topology description string (Italian).
    /// Example: "MacBook Pro → USB 10 Gb/s → Hub USB 5 Gb/s → SanDisk SSD"
    public static func topologyDescription(for topology: [USBTopologyNode]) -> String {
        let meaningfulNodes = topology.filter { node in
            node.className == "IOUSBHostDevice" || node.className.contains("XHCI")
        }
        
        guard !meaningfulNodes.isEmpty else { return "" }
        
        var parts: [String] = []
        for node in meaningfulNodes.reversed() {
            if node.className.contains("XHCI") {
                parts.append("Mac")
            } else if node.isHub {
                let speed = node.linkSpeedBps != nil ? " \(LinkSpeedService.formatSpeed(node.linkSpeedBps!))" : ""
                parts.append("\(node.displayName)\(speed)")
            } else {
                let speed = node.linkSpeedBps != nil ? " \(LinkSpeedService.formatSpeed(node.linkSpeedBps!))" : ""
                parts.append("\(node.displayName)\(speed)")
            }
        }
        
        return parts.joined(separator: " → ")
    }
}
