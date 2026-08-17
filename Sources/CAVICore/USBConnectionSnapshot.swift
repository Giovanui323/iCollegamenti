import Foundation

/// A USB peripheral observed by macOS. It can exist without a mounted storage volume.
public struct USBConnectionSnapshot: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let displayName: String
    public let vendorID: Int?
    public let productID: Int?
    public let serialNumber: String?
    public let locationID: Int?
    public let linkSpeedBps: UInt64?
    public let mountedVolumeBSDName: String?
    public let bsdName: String?
    public let isMounted: Bool
    public let isStorageDevice: Bool
    public let mountPath: String?

    public init(id: String, displayName: String, vendorID: Int?, productID: Int?, serialNumber: String?, locationID: Int?, linkSpeedBps: UInt64?, mountedVolumeBSDName: String?, bsdName: String? = nil, isMounted: Bool = false, isStorageDevice: Bool = false, mountPath: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.locationID = locationID
        self.linkSpeedBps = linkSpeedBps
        self.mountedVolumeBSDName = mountedVolumeBSDName
        self.bsdName = bsdName ?? mountedVolumeBSDName
        self.isMounted = isMounted || mountedVolumeBSDName != nil
        self.isStorageDevice = isStorageDevice || mountedVolumeBSDName != nil || bsdName != nil
        self.mountPath = mountPath
    }

    public var isBenchmarkable: Bool { isMounted && mountPath != nil && !mountPath!.isEmpty }
}
