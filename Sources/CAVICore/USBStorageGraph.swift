import Foundation

public struct RawUSBIdentity: Hashable, Sendable {
    public let vendorID: Int?
    public let productID: Int?
    public let serialNumber: String?
    public let locationID: Int?
    public let registryEntryID: UInt64?
    public let registryPath: String?

    public init(
        vendorID: Int?,
        productID: Int?,
        serialNumber: String?,
        locationID: Int?,
        registryEntryID: UInt64?,
        registryPath: String?
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = Self.nonEmpty(serialNumber)
        self.locationID = locationID
        self.registryEntryID = registryEntryID
        self.registryPath = Self.nonEmpty(registryPath)
    }

    fileprivate static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

public enum RawUSBNodeKind: String, Hashable, Sendable {
    case host
    case controller
    case rootHub
    case externalHub
    case bridge
    case physicalDevice
}

public struct RawUSBRegistryNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let parentID: String?
    public let kind: RawUSBNodeKind
    public let identity: RawUSBIdentity?
    public let displayName: String
    public let negotiatedSpeedBps: UInt64?

    public init(
        id: String,
        parentID: String?,
        kind: RawUSBNodeKind,
        identity: RawUSBIdentity?,
        displayName: String,
        negotiatedSpeedBps: UInt64?
    ) {
        self.id = id
        self.parentID = parentID
        self.kind = kind
        self.identity = identity
        self.displayName = displayName
        self.negotiatedSpeedBps = negotiatedSpeedBps
    }

    public static func host(id: String) -> Self {
        .init(id: id, parentID: nil, kind: .host, identity: nil, displayName: "Mac", negotiatedSpeedBps: nil)
    }

    public static func controller(id: String, parentID: String) -> Self {
        .init(id: id, parentID: parentID, kind: .controller, identity: nil, displayName: "USB Controller", negotiatedSpeedBps: nil)
    }

    public static func rootHub(id: String, parentID: String) -> Self {
        .init(id: id, parentID: parentID, kind: .rootHub, identity: nil, displayName: "USB Root Hub", negotiatedSpeedBps: nil)
    }
}

public enum RawStorageMediaKind: String, Hashable, Sendable {
    case wholeDisk
    case partition
    case volume
}

public struct RawStorageMediaObservation: Identifiable, Hashable, Sendable {
    public let bsdName: String
    public let parentBSDName: String?
    public let kind: RawStorageMediaKind
    public let registryEntryID: UInt64?
    public let registryAncestorEntryID: UInt64?
    public let registryAncestorPath: String?
    public let mediaUUID: String?
    public let volumeUUID: String?
    public let fileSystem: String?
    public let volumeName: String?
    public let mountPath: String?
    public let capacityBytes: UInt64?
    public let freeSpaceBytes: UInt64?
    public let isReadOnly: Bool

    public var id: String { "\(kind.rawValue):\(bsdName):\(volumeUUID ?? mediaUUID ?? "")" }

    public init(
        bsdName: String,
        parentBSDName: String?,
        kind: RawStorageMediaKind,
        registryEntryID: UInt64?,
        registryAncestorEntryID: UInt64?,
        registryAncestorPath: String?,
        mediaUUID: String?,
        volumeUUID: String?,
        fileSystem: String?,
        volumeName: String?,
        mountPath: String?,
        capacityBytes: UInt64?,
        freeSpaceBytes: UInt64?,
        isReadOnly: Bool
    ) {
        self.bsdName = bsdName
        self.parentBSDName = parentBSDName
        self.kind = kind
        self.registryEntryID = registryEntryID
        self.registryAncestorEntryID = registryAncestorEntryID
        self.registryAncestorPath = RawUSBIdentity.nonEmpty(registryAncestorPath)
        self.mediaUUID = RawUSBIdentity.nonEmpty(mediaUUID)
        self.volumeUUID = RawUSBIdentity.nonEmpty(volumeUUID)
        self.fileSystem = RawUSBIdentity.nonEmpty(fileSystem)
        self.volumeName = RawUSBIdentity.nonEmpty(volumeName)
        self.mountPath = RawUSBIdentity.nonEmpty(mountPath)
        self.capacityBytes = capacityBytes
        self.freeSpaceBytes = freeSpaceBytes
        self.isReadOnly = isReadOnly
    }
}

public struct RawUSBStorageObservationSet: Hashable, Sendable {
    public var registryNodes: [RawUSBRegistryNode]
    public var media: [RawStorageMediaObservation]

    public init(registryNodes: [RawUSBRegistryNode], media: [RawStorageMediaObservation]) {
        self.registryNodes = registryNodes
        self.media = media
    }
}

public struct USBPhysicalIdentity: Hashable, Sendable {
    public let vendorID: Int?
    public let productID: Int?
    public let serialNumber: String?
    public let locationID: Int?
    public let registryEntryID: UInt64?
    public let registryPath: String?

    public init(_ raw: RawUSBIdentity) {
        vendorID = raw.vendorID
        productID = raw.productID
        serialNumber = raw.serialNumber
        locationID = raw.locationID
        registryEntryID = raw.registryEntryID
        registryPath = raw.registryPath
    }

    /// An identity suitable for comparing observations across refreshes. An
    /// I/O Registry entry identifier deliberately does not participate: it is
    /// only meaningful while the current registry snapshot is alive.
    public var persistentIdentityKey: String? {
        if let serialNumber, let vendorID, let productID { return "serial:\(vendorID):\(productID):\(serialNumber)" }
        if let locationID, let vendorID, let productID { return "location:\(vendorID):\(productID):\(locationID)" }
        if let registryPath { return "path:\(registryPath)" }
        return nil
    }

    /// A transient key for one reconciliation pass. It must never be persisted
    /// or used as cross-refresh device identity.
    public var sessionIdentityKey: String {
        if let registryEntryID { return "registry-session:\(registryEntryID)" }
        return persistentIdentityKey ?? "unknown"
    }
}

public struct ReconciledUSBTopologyNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: RawUSBNodeKind
    public let displayName: String
    public let negotiatedSpeedBps: UInt64?
    public let identity: USBPhysicalIdentity?

    public var isController: Bool { kind == .controller }
    public var isRootHub: Bool { kind == .rootHub }
    public var isHub: Bool { kind == .rootHub || kind == .externalHub }

    init(_ node: RawUSBRegistryNode) {
        id = node.id
        kind = node.kind
        displayName = node.displayName
        negotiatedSpeedBps = node.negotiatedSpeedBps
        identity = node.identity.map(USBPhysicalIdentity.init)
    }
}

public struct MountedVolume: Identifiable, Hashable, Sendable {
    public let id: String
    public let bsdName: String
    public let volumeUUID: String?
    public let fileSystem: String?
    public let volumeName: String?
    public let mountPath: String
    public let capacityBytes: UInt64?
    public let freeSpaceBytes: UInt64?
    public let isReadOnly: Bool

    public var isMounted: Bool { !mountPath.isEmpty }
}

public struct StoragePartition: Identifiable, Hashable, Sendable {
    public let id: String
    public let bsdName: String
    public let volumes: [MountedVolume]
}

public struct StorageDisk: Identifiable, Hashable, Sendable {
    public let id: String
    public let bsdName: String
    public let capacityBytes: UInt64?
    public let partitions: [StoragePartition]
}

public struct USBUplink: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let negotiatedSpeedBps: UInt64?
}

public struct USBPhysicalDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let identity: USBPhysicalIdentity
    public let displayName: String
    public let negotiatedLinkSpeedBps: UInt64?
    public let technicalTopology: [ReconciledUSBTopologyNode]
    public let disks: [StorageDisk]

    public var isExternal: Bool { true }
    public var persistentIdentityKey: String? { identity.persistentIdentityKey }
}

public struct ReconciledUSBStorageGraph: Hashable, Sendable {
    public let physicalDevices: [USBPhysicalDevice]
    public let uplinks: [USBUplink]

    public init(physicalDevices: [USBPhysicalDevice], uplinks: [USBUplink]) {
        self.physicalDevices = physicalDevices
        self.uplinks = uplinks
    }
}

public enum USBStorageReconciler {
    public static func reconcile(_ observations: RawUSBStorageObservationSet) -> ReconciledUSBStorageGraph {
        let nodesByID = observations.registryNodes.reduce(into: [String: RawUSBRegistryNode]()) { nodes, node in
            nodes[node.id] = nodes[node.id] ?? node
        }
        let endpointGroups = groupedEndpoints(observations.registryNodes)
        let mediaByEndpoint = associatedMedia(
            observations.media,
            endpointGroups: endpointGroups
        )

        let physicalDevices = endpointGroups.compactMap { group -> USBPhysicalDevice? in
            guard let primary = group.first, let rawIdentity = primary.identity else { return nil }
            let topology = technicalTopology(for: primary, nodesByID: nodesByID)
            let groupMedia = group.flatMap { mediaByEndpoint[$0.id] ?? [] }
            return USBPhysicalDevice(
                id: USBPhysicalIdentity(rawIdentity).sessionIdentityKey == "unknown" ? primary.id : USBPhysicalIdentity(rawIdentity).sessionIdentityKey,
                identity: USBPhysicalIdentity(rawIdentity),
                displayName: primary.displayName,
                negotiatedLinkSpeedBps: primary.negotiatedSpeedBps,
                technicalTopology: topology,
                disks: storageDisks(from: groupMedia)
            )
        }.sorted { $0.id < $1.id }

        let observedUplinks = observations.registryNodes.compactMap { node -> USBUplink? in
            guard node.kind == .externalHub else { return nil }
            return USBUplink(id: node.id, displayName: node.displayName, negotiatedSpeedBps: node.negotiatedSpeedBps)
        }
        let uplinks = observedUplinks.reduce(into: [String: USBUplink]()) { unique, uplink in
            unique[uplink.id] = unique[uplink.id] ?? uplink
        }.values.sorted { $0.id < $1.id }

        return ReconciledUSBStorageGraph(physicalDevices: physicalDevices, uplinks: uplinks)
    }

    private static func groupedEndpoints(_ nodes: [RawUSBRegistryNode]) -> [[RawUSBRegistryNode]] {
        let endpoints = nodes.filter { $0.kind == .physicalDevice || $0.kind == .bridge }
            .sorted { $0.id < $1.id }
        var groups: [[RawUSBRegistryNode]] = []

        for endpoint in endpoints {
            guard let identity = endpoint.identity else { continue }
            let matches = groups.indices.filter { index in
                groups[index].contains { candidate in
                    guard let candidateIdentity = candidate.identity else { return false }
                    return matchStrength(identity, candidateIdentity) != nil
                }
            }
            if matches.count == 1 {
                groups[matches[0]].append(endpoint)
            } else {
                groups.append([endpoint])
            }
        }
        return groups
    }

    private static func associatedMedia(
        _ media: [RawStorageMediaObservation],
        endpointGroups: [[RawUSBRegistryNode]]
    ) -> [String: [RawStorageMediaObservation]] {
        var result: [String: [RawStorageMediaObservation]] = [:]
        for item in media {
            let matches = endpointGroups.filter { group in
                group.contains { endpoint in
                    guard let identity = endpoint.identity else { return false }
                    if let ancestor = item.registryAncestorEntryID, ancestor == identity.registryEntryID { return true }
                    if let path = item.registryAncestorPath, path == identity.registryPath { return true }
                    return false
                }
            }
            guard matches.count == 1 else { continue }
            for endpoint in matches[0] {
                result[endpoint.id, default: []].append(item)
            }
        }
        return result
    }

    private static func technicalTopology(
        for endpoint: RawUSBRegistryNode,
        nodesByID: [String: RawUSBRegistryNode]
    ) -> [ReconciledUSBTopologyNode] {
        var path: [RawUSBRegistryNode] = []
        var current: RawUSBRegistryNode? = endpoint
        var seen = Set<String>()
        while let node = current, seen.insert(node.id).inserted {
            path.append(node)
            current = node.parentID.flatMap { nodesByID[$0] }
        }
        return path.reversed().map(ReconciledUSBTopologyNode.init)
    }

    private static func storageDisks(from media: [RawStorageMediaObservation]) -> [StorageDisk] {
        // A single IOMedia can be observed by both Disk Arbitration and an
        // IOKit traversal in the same snapshot.  Its optional UUID metadata
        // is not guaranteed to be populated in both records, so use the
        // storage address rather than `RawStorageMediaObservation.id`.
        var mediaByStorageAddress: [String: RawStorageMediaObservation] = [:]
        for candidate in media {
            let address = "\(candidate.kind.rawValue):\(candidate.bsdName):\(candidate.parentBSDName ?? "")"
            if let existing = mediaByStorageAddress[address] {
                mediaByStorageAddress[address] = preferredMedia(existing, candidate)
            } else {
                mediaByStorageAddress[address] = candidate
            }
        }
        let uniqueMedia = Array(mediaByStorageAddress.values)
        let partitions = uniqueMedia.filter { $0.kind == .partition }
        let volumes = uniqueMedia.filter { $0.kind == .volume }

        return uniqueMedia.filter { $0.kind == .wholeDisk }.map { disk in
            let diskPartitions = partitions.filter { $0.parentBSDName == disk.bsdName }.map { partition in
                let explicitVolumes = volumes.filter { $0.parentBSDName == partition.bsdName }
                let childVolumes = explicitVolumes.isEmpty ? [partition] : explicitVolumes
                return StoragePartition(
                    id: partition.bsdName,
                    bsdName: partition.bsdName,
                    volumes: childVolumes.compactMap(mountedVolume)
                )
            }.sorted { $0.bsdName < $1.bsdName }
            return StorageDisk(
                id: disk.bsdName,
                bsdName: disk.bsdName,
                capacityBytes: disk.capacityBytes,
                partitions: diskPartitions
            )
        }.sorted { $0.bsdName < $1.bsdName }
    }

    private static func preferredMedia(
        _ left: RawStorageMediaObservation,
        _ right: RawStorageMediaObservation
    ) -> RawStorageMediaObservation {
        func completeness(of item: RawStorageMediaObservation) -> Int {
            [
                item.registryEntryID != nil,
                item.registryAncestorEntryID != nil,
                item.registryAncestorPath != nil,
                item.mediaUUID != nil,
                item.volumeUUID != nil,
                item.fileSystem != nil,
                item.volumeName != nil,
                item.mountPath != nil,
                item.capacityBytes != nil,
                item.freeSpaceBytes != nil
            ].filter { $0 }.count
        }
        return completeness(of: right) > completeness(of: left) ? right : left
    }

    private static func mountedVolume(from media: RawStorageMediaObservation) -> MountedVolume? {
        guard let mountPath = media.mountPath else { return nil }
        return MountedVolume(
            id: media.volumeUUID ?? "\(media.bsdName):\(mountPath)",
            bsdName: media.bsdName,
            volumeUUID: media.volumeUUID,
            fileSystem: media.fileSystem,
            volumeName: media.volumeName,
            mountPath: mountPath,
            capacityBytes: media.capacityBytes,
            freeSpaceBytes: media.freeSpaceBytes,
            isReadOnly: media.isReadOnly
        )
    }

    private enum PhysicalMatchStrength: Int {
        case registryEntry = 4
        case serialWithVendorProduct = 3
        case locationWithVendorProduct = 2
        case registryPath = 1
    }

    private static func matchStrength(_ left: RawUSBIdentity, _ right: RawUSBIdentity) -> PhysicalMatchStrength? {
        if let leftEntry = left.registryEntryID, let rightEntry = right.registryEntryID {
            return leftEntry == rightEntry ? .registryEntry : nil
        }
        if let leftLocation = left.locationID, let rightLocation = right.locationID,
           leftLocation != rightLocation {
            return nil
        }
        if let leftSerial = left.serialNumber, let rightSerial = right.serialNumber {
            guard leftSerial == rightSerial, sameVendorProduct(left, right) else { return nil }
            return .serialWithVendorProduct
        }
        if let leftLocation = left.locationID, let rightLocation = right.locationID {
            guard leftLocation == rightLocation, sameVendorProduct(left, right) else { return nil }
            return .locationWithVendorProduct
        }
        if let leftPath = left.registryPath, let rightPath = right.registryPath, leftPath == rightPath {
            return .registryPath
        }
        return nil
    }

    /// Uses exactly the same ranked rules as grouping in the current registry
    /// snapshot. It is intended for invariant checks, not persistence.
    public static func areEquivalent(_ left: USBPhysicalDevice, _ right: USBPhysicalDevice) -> Bool {
        matchStrength(
            RawUSBIdentity(
                vendorID: left.identity.vendorID,
                productID: left.identity.productID,
                serialNumber: left.identity.serialNumber,
                locationID: left.identity.locationID,
                registryEntryID: left.identity.registryEntryID,
                registryPath: left.identity.registryPath
            ),
            RawUSBIdentity(
                vendorID: right.identity.vendorID,
                productID: right.identity.productID,
                serialNumber: right.identity.serialNumber,
                locationID: right.identity.locationID,
                registryEntryID: right.identity.registryEntryID,
                registryPath: right.identity.registryPath
            )
        ) != nil
    }

    private static func sameVendorProduct(_ left: RawUSBIdentity, _ right: RawUSBIdentity) -> Bool {
        left.vendorID == right.vendorID && left.productID == right.productID
    }
}
