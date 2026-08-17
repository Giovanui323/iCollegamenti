import Foundation
import SwiftUI
import CAVICore

// MARK: - Helpers

fileprivate func formatSpeed(bps: UInt64?) -> String {
    guard let bps = bps else { return "Sconosciuto" }
    
    if bps >= 1_000_000_000 {
        let gbps = Double(bps) / 1_000_000_000.0
        return gbps.truncatingRemainder(dividingBy: 1.0) == 0 ? String(format: "%.0f Gb/s", gbps) : String(format: "%.1f Gb/s", gbps)
    } else if bps >= 1_000_000 {
        let mbps = Double(bps) / 1_000_000.0
        return String(format: "%.0f Mb/s", mbps)
    } else {
        return "\(bps) bps"
    }
}

// MARK: - Enums

public enum LinkSpeedRating: Sendable, Hashable, Codable {
    case verySlowUSB1
    case slowUSB2
    case goodUSB3
    case greatUSB3Gen2
    case excellentUSB3Gen2x2
    case excellentTB3USB4
    case excellentTB5
    case unknown

    public var label: String {
        switch self {
        case .verySlowUSB1, .slowUSB2: return "MOLTO LENTO"
        case .goodUSB3: return "BUONO"
        case .greatUSB3Gen2: return "OTTIMO"
        case .excellentUSB3Gen2x2, .excellentTB3USB4, .excellentTB5: return "ECCELLENTE"
        case .unknown: return "SCONOSCIUTO"
        }
    }

    public var emoji: String {
        switch self {
        case .verySlowUSB1, .slowUSB2: return "🔴"
        case .goodUSB3: return "🟡"
        case .greatUSB3Gen2, .excellentUSB3Gen2x2, .excellentTB3USB4, .excellentTB5: return "🟢"
        case .unknown: return "⚪"
        }
    }

    public var color: Color {
        switch self {
        case .verySlowUSB1, .slowUSB2: return .red
        case .goodUSB3: return .orange
        case .greatUSB3Gen2, .excellentUSB3Gen2x2, .excellentTB3USB4, .excellentTB5: return .green
        case .unknown: return .gray
        }
    }

    public var protocolDescription: String {
        switch self {
        case .verySlowUSB1: return "USB 1.1 Full-Speed"
        case .slowUSB2: return "USB 2.0 Hi-Speed"
        case .goodUSB3: return "USB SuperSpeed 5 Gbps"
        case .greatUSB3Gen2: return "USB SuperSpeed 10 Gbps"
        case .excellentUSB3Gen2x2: return "USB SuperSpeed 20 Gbps"
        case .excellentTB3USB4: return "Thunderbolt / USB4 40 Gbps"
        case .excellentTB5: return "Thunderbolt 5 / USB4 80 Gbps"
        case .unknown: return "Sconosciuto"
        }
    }

    /// Classification of the negotiated data link, not an assertion about the cable alone.
    public var connectionType: String {
        switch self {
        case .verySlowUSB1: return "USB 1.1"
        case .slowUSB2: return "USB 2.0 Hi-Speed"
        case .goodUSB3: return "USB 3.2 Gen 1 (5 Gb/s)"
        case .greatUSB3Gen2: return "USB 3.2 Gen 2 (10 Gb/s)"
        case .excellentUSB3Gen2x2: return "USB 3.2 Gen 2×2 (20 Gb/s)"
        case .excellentTB3USB4: return "USB4 / Thunderbolt (40 Gb/s)"
        case .excellentTB5: return "USB4 / Thunderbolt 5 (80 Gb/s)"
        case .unknown: return "Tipo dati non determinabile"
        }
    }

    public var detailedDescription: String {
        switch self {
        case .verySlowUSB1: return "Estremamente lento. Inadatto per il trasferimento dati."
        case .slowUSB2: return "Non consigliato per SSD esterni. Velocità limitata a circa 40 MB/s reali. Forse stai usando un cavo di ricarica invece di un cavo dati."
        case .goodUSB3: return "Velocità adeguata per dischi rigidi e SSD di base."
        case .greatUSB3Gen2: return "Ottima velocità per la maggior parte degli SSD esterni NVMe."
        case .excellentUSB3Gen2x2: return "Velocità eccellente. Richiede porte compatibili 2x2."
        case .excellentTB3USB4: return "Velocità massima per periferiche Thunderbolt e USB4."
        case .excellentTB5: return "Prestazioni di nuova generazione senza compromessi."
        case .unknown: return "Impossibile determinare la velocità del collegamento."
        }
    }

    public var theoreticalMaxMBps: Double {
        switch self {
        case .verySlowUSB1: return 1.5
        case .slowUSB2: return 60.0
        case .goodUSB3: return 625.0
        case .greatUSB3Gen2: return 1250.0
        case .excellentUSB3Gen2x2: return 2500.0
        case .excellentTB3USB4: return 5000.0
        case .excellentTB5: return 10000.0
        case .unknown: return 0.0
        }
    }

    public static func from(speedBps: UInt64?) -> LinkSpeedRating {
        guard let speed = speedBps else { return .unknown }
        if speed >= 80_000_000_000 { return .excellentTB5 }
        if speed >= 40_000_000_000 { return .excellentTB3USB4 }
        if speed >= 20_000_000_000 { return .excellentUSB3Gen2x2 }
        if speed >= 10_000_000_000 { return .greatUSB3Gen2 }
        if speed >= 5_000_000_000 { return .goodUSB3 }
        if speed >= 480_000_000 { return .slowUSB2 }
        if speed >= 12_000_000 { return .verySlowUSB1 }
        return .unknown
    }
}

// MARK: - HDMI / Video Display Models

public enum HDMICableGrade: String, Sendable, Hashable, Codable {
    case hdmi1_4 = "HDMI 1.4 Standard"
    case hdmi2_0 = "HDMI 2.0 Premium High Speed"
    case hdmi2_1 = "HDMI 2.1 Ultra High Speed"
    case dpAltMode = "DisplayPort / USB4 Alt Mode"
    case unknown = "Sconosciuto"
    
    public var label: String {
        switch self {
        case .hdmi1_4: return "HDMI 1.4 (High Speed - Max 4K 30Hz)"
        case .hdmi2_0: return "HDMI 2.0 (Premium High Speed - Max 4K 60Hz)"
        case .hdmi2_1: return "HDMI 2.1 (Ultra High Speed - Max 4K 120Hz / 8K)"
        case .dpAltMode: return "DisplayPort / USB-C Video Alt Mode"
        case .unknown: return "Sconosciuto"
        }
    }
    
    public var maxBandwidthGbps: Double {
        switch self {
        case .hdmi1_4: return 10.2
        case .hdmi2_0: return 18.0
        case .hdmi2_1: return 48.0
        case .dpAltMode: return 32.4
        case .unknown: return 0.0
        }
    }
    
    public var emoji: String {
        switch self {
        case .hdmi1_4: return "🔴"
        case .hdmi2_0: return "🟡"
        case .hdmi2_1, .dpAltMode: return "🟢"
        case .unknown: return "⚪"
        }
    }
    
    public var color: Color {
        switch self {
        case .hdmi1_4: return .red
        case .hdmi2_0: return .orange
        case .hdmi2_1, .dpAltMode: return .green
        case .unknown: return .gray
        }
    }
    
    public var recommendationText: String {
        switch self {
        case .hdmi1_4:
            return "Classe minima stimata per questo segnale: High Speed. Adeguata fino a 4K 30Hz o 1080p 60Hz."
        case .hdmi2_0:
            return "Classe minima stimata per questo segnale: Premium High Speed (18 Gb/s). Per 4K 120Hz/144Hz serve Ultra High Speed."
        case .hdmi2_1:
            return "Classe minima stimata per questo segnale: Ultra High Speed (48 Gb/s), adatta a 4K 120Hz/144Hz e 8K 60Hz HDR."
        case .dpAltMode:
            return "Il segnale richiede una connessione DisplayPort/USB-C ad alta banda."
        case .unknown:
            return "Dati insufficienti per stimare il requisito del collegamento."
        }
    }

    public static func required(forEstimatedBandwidthGbps bandwidth: Double) -> Self {
        switch bandwidth {
        case ..<10.2: .hdmi1_4
        case ..<18.0: .hdmi2_0
        default: .hdmi2_1
        }
    }
}

public struct HDMIDisplayDevice: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let displayID: UInt32
    public let displayName: String
    public let widthPixels: Int
    public let heightPixels: Int
    public let refreshRateHz: Double
    public let isHDRSupported: Bool
    public let colorDepthBits: Int
    public let connectionTransport: String
    public let estimatedBandwidthGbps: Double
    public let cableGrade: HDMICableGrade
    
    public var parsedEDID: ParsedEDID?
    public var manufacturerFromEDID: String?
    public var modelFromEDID: String?
    public var serialFromEDID: String?
    public var nativeResolution: EDIDResolution?
    public var supportsHDR10: Bool
    public var supportsHLG: Bool
    public var vrrRange: VRRRange?
    
    public init(id: UUID = UUID(), displayID: UInt32, displayName: String, widthPixels: Int, heightPixels: Int, refreshRateHz: Double, isHDRSupported: Bool, colorDepthBits: Int, connectionTransport: String, estimatedBandwidthGbps: Double, cableGrade: HDMICableGrade) {
        self.id = id
        self.displayID = displayID
        self.displayName = displayName
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.refreshRateHz = refreshRateHz
        self.isHDRSupported = isHDRSupported
        self.colorDepthBits = colorDepthBits
        self.connectionTransport = connectionTransport
        self.estimatedBandwidthGbps = estimatedBandwidthGbps
        self.cableGrade = cableGrade
        
        // New fields defaults
        self.parsedEDID = nil
        self.manufacturerFromEDID = nil
        self.modelFromEDID = nil
        self.serialFromEDID = nil
        self.nativeResolution = nil
        self.supportsHDR10 = false
        self.supportsHLG = false
        self.vrrRange = nil
    }
    
    public var resolutionFormatted: String {
        "\(widthPixels) x \(heightPixels) @ \(Int(round(refreshRateHz)))Hz"
    }
}

// MARK: - Models

public struct PowerInfo: Codable, Hashable, Sendable {
    public let powerSinkAllocationMw: Int?
    public let busPowerAvailableMw: Int?
    
    public init(powerSinkAllocationMw: Int? = nil, busPowerAvailableMw: Int? = nil) {
        self.powerSinkAllocationMw = powerSinkAllocationMw
        self.busPowerAvailableMw = busPowerAvailableMw
    }
}

public enum ChargingAssessment: Sendable, Hashable {
    case observed(watts: Double)
    case unavailable

    public var title: String {
        switch self {
        case .observed(let watts) where watts >= 15: return "Ricarica rapida osservata: \(String(format: "%.1f", watts)) W"
        case .observed(let watts): return "Alimentazione osservata: \(String(format: "%.1f", watts)) W"
        case .unavailable: return "Potenza di ricarica non rilevabile"
        }
    }

    public var detail: String {
        switch self {
        case .observed: return "È la potenza allocata in questa connessione, non il wattaggio massimo certificato del cavo."
        case .unavailable: return "Il Mac non ha esposto dati Power Delivery/e-marker per questo collegamento. La velocità dati non determina i watt massimi."
        }
    }
}

public struct USBTopologyNode: Codable, Hashable, Sendable {
    public let className: String
    public var vendorName: String?
    public let productName: String?
    public let vendorID: Int?
    public let productID: Int?
    public let serialNumber: String?
    public let linkSpeedBps: UInt64?
    public let isHub: Bool
    public let locationID: Int?

    public init(className: String, vendorName: String? = nil, productName: String? = nil, vendorID: Int? = nil, productID: Int? = nil, serialNumber: String? = nil, linkSpeedBps: UInt64? = nil, isHub: Bool, locationID: Int? = nil) {
        self.className = className
        self.vendorName = vendorName
        self.productName = productName
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.linkSpeedBps = linkSpeedBps
        self.isHub = isHub
        self.locationID = locationID
    }

    public var linkSpeedFormatted: String? {
        guard let speed = linkSpeedBps else { return nil }
        return formatSpeed(bps: speed)
    }

    public var displayName: String {
        if let pName = productName, !pName.isEmpty { return pName }
        if let vName = vendorName, !vName.isEmpty { return "\(vName) Device" }
        return className
    }
}

// MARK: - Cable Category

public enum CableCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case data = "Dati USB"
    case video = "Video (HDMI/DP)"
    case charging = "Ricarica Power Delivery"
    
    public var id: Self { self }
    public var symbol: String {
        switch self {
        case .data: return "cable.connector"
        case .video: return "display"
        case .charging: return "bolt.batteryblock"
        }
    }
    
    public func localizedName(using lm: LanguageManager) -> String {
        switch self {
        case .data: return lm.t("USB Data", "Dati USB")
        case .video: return "Video (HDMI/DP)"
        case .charging: return lm.t("Power Delivery", "Ricarica Power Delivery")
        }
    }
}

/// A cable intentionally registered by the user. Its code identifies the
/// catalog entry; it is not inferred from an unverified USB connection.
public struct CableProfile: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let code: String
    public var name: String
    public let createdAt: Date
    public var lastUsedAt: Date
    public var confirmedConnectionFingerprints: Set<String>

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        confirmedConnectionFingerprints: Set<String> = []
    ) {
        self.id = id
        self.code = CableIdentityPolicy.code(for: id)
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.confirmedConnectionFingerprints = confirmedConnectionFingerprints
    }
}

public struct DriveDevice: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// Stable identity of the reconciled physical USB device, when this row
    /// originated from the USB/storage graph rather than a legacy source.
    public let physicalDeviceID: String?
    /// Simplified breadcrumb derived by `USBTopologyNormalizer` while the full
    /// technical path remains available in `usbTopology` for inspection.
    public let topologyBreadcrumb: String?
    public let volumeName: String
    public let mountPath: String
    public let bsdName: String
    public let capacity: UInt64
    public let freeSpace: UInt64
    public let vendorID: Int?
    public let productID: Int?
    public let serialNumber: String?
    public var vendorName: String?
    public let productName: String?
    public let negotiatedSpeedBps: UInt64?
    public let protocol_: String?
    public let isInternal: Bool
    public let fileSystem: String?
    public let isSolidState: Bool?
    public let locationID: Int?
    public let usbTopology: [USBTopologyNode]
    public let powerInfo: PowerInfo?
    public let isStorageDevice: Bool
    public let isMounted: Bool
    public let storageConnectionKind: StorageConnectionKind
    /// Optional technical evidence captured for the current connection. It is
    /// intentionally absent for hardware that does not expose these details.
    public let connectionSnapshot: ConnectionSnapshot?

    public init(id: UUID = UUID(), physicalDeviceID: String? = nil, topologyBreadcrumb: String? = nil, volumeName: String = "", mountPath: String = "", bsdName: String = "", capacity: UInt64 = 0, freeSpace: UInt64 = 0, vendorID: Int? = nil, productID: Int? = nil, serialNumber: String? = nil, vendorName: String? = nil, productName: String? = nil, negotiatedSpeedBps: UInt64? = nil, protocol_: String? = nil, isInternal: Bool = false, fileSystem: String? = nil, isSolidState: Bool? = nil, locationID: Int? = nil, usbTopology: [USBTopologyNode] = [], powerInfo: PowerInfo? = nil, isStorageDevice: Bool = true, isMounted: Bool? = nil, storageConnectionKind: StorageConnectionKind = .usbOrThunderbolt, connectionSnapshot: ConnectionSnapshot? = nil) {
        self.id = id
        self.physicalDeviceID = physicalDeviceID
        self.topologyBreadcrumb = topologyBreadcrumb
        self.volumeName = volumeName
        self.mountPath = mountPath
        self.bsdName = bsdName
        self.capacity = capacity
        self.freeSpace = freeSpace
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.vendorName = vendorName
        self.productName = productName
        self.negotiatedSpeedBps = negotiatedSpeedBps
        self.protocol_ = protocol_
        self.isInternal = isInternal
        self.fileSystem = fileSystem
        self.isSolidState = isSolidState
        self.locationID = locationID
        self.usbTopology = usbTopology
        self.powerInfo = powerInfo
        self.isStorageDevice = isStorageDevice
        self.isMounted = isMounted ?? !mountPath.isEmpty
        self.storageConnectionKind = storageConnectionKind
        self.connectionSnapshot = connectionSnapshot
    }

    public var isMountedVolume: Bool { isMounted && !mountPath.isEmpty }

    public var canRunBenchmark: Bool {
        BenchmarkEligibility.canRun(isStorageDevice: isStorageDevice, isMounted: isMounted, mountPath: mountPath)
    }

    public func connectionDescription(using languageManager: LanguageManager) -> String {
        switch storageConnectionKind {
        case .usbOrThunderbolt:
            return languageManager.t("USB or Thunderbolt drive", "Unità USB o Thunderbolt")
        case .integratedSDReader:
            return languageManager.t(
                "Integrated SD reader — no cable to diagnose",
                "Lettore SD integrato — nessun cavo da diagnosticare"
            )
        }
    }

    public var capacityFormatted: String {
        guard isStorageDevice && capacity > 0 else { return "Periferica USB" }
        return ByteCountFormatter.string(fromByteCount: Int64(capacity), countStyle: .file)
    }

    public var freeSpaceFormatted: String {
        guard isStorageDevice && capacity > 0 else { return "N/D" }
        return ByteCountFormatter.string(fromByteCount: Int64(freeSpace), countStyle: .file)
    }

    public var negotiatedSpeedFormatted: String {
        formatSpeed(bps: negotiatedSpeedBps)
    }

    public var speedRating: LinkSpeedRating {
        LinkSpeedRating.from(speedBps: negotiatedSpeedBps)
    }

    public var chargingAssessment: ChargingAssessment {
        guard let milliwatts = powerInfo?.powerSinkAllocationMw, milliwatts > 0 else { return .unavailable }
        return .observed(watts: Double(milliwatts) / 1_000.0)
    }

    /// Best-effort signature of a *connection*, not a cable serial number. macOS normally exposes
    /// the attached device and USB path, but not the Type-C e-marker identity of the cable.
    public var connectionFingerprint: String {
        let topology = usbTopology.map {
            [
                $0.className,
                String($0.vendorID ?? 0),
                String($0.productID ?? 0),
                $0.serialNumber ?? "no-serial",
                String($0.locationID ?? 0),
                String($0.linkSpeedBps ?? 0)
            ].joined(separator: ":")
        }.joined(separator: "/")
        return [
            String(vendorID ?? 0),
            String(productID ?? 0),
            serialNumber ?? "no-serial",
            String(locationID ?? 0),
            protocol_?.lowercased() ?? "no-protocol",
            String(negotiatedSpeedBps ?? 0),
            String(powerInfo?.powerSinkAllocationMw ?? 0),
            topology
        ].joined(separator: "|")
    }

    /// A stable identity needs either the device serial number or a sufficiently detailed USB path.
    /// Otherwise two physically different, generic devices could look identical to macOS.
    public var hasReliableConnectionIdentity: Bool {
        if let serialNumber, !serialNumber.isEmpty { return true }
        return vendorID != nil && productID != nil && locationID != nil && !usbTopology.isEmpty
    }

    /// Uses the connection time only as a fallback session discriminator for generic hardware.
    public func recognitionFingerprint(connectedAt: Date) -> String {
        guard !hasReliableConnectionIdentity else { return connectionFingerprint }
        return "\(connectionFingerprint)|session:\(Int(connectedAt.timeIntervalSince1970))"
    }

    public var displayName: String {
        let base: String = {
            if let pName = productName, !pName.isEmpty { return pName }
            if !volumeName.isEmpty { return volumeName }
            if let vName = vendorName, !vName.isEmpty { return "\(vName) Device" }
            return "Periferica USB"
        }()
        if !volumeName.isEmpty && volumeName != base && volumeName != bsdName {
            return "\(base) — \(volumeName)"
        }
        return base
    }
}

public struct ReferenceDevice: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let vendorID: Int?
    public let productID: Int?
    public let serialNumber: String?
    public let vendorName: String?
    public let productName: String?
    public let maxObservedSpeedBps: UInt64
    public let maxBenchmarkReadMBps: Double?
    public let maxBenchmarkWriteMBps: Double?
    public let dateAdded: Date
    public let dateLastSeen: Date

    public init(id: UUID = UUID(), vendorID: Int? = nil, productID: Int? = nil, serialNumber: String? = nil, vendorName: String? = nil, productName: String? = nil, maxObservedSpeedBps: UInt64, maxBenchmarkReadMBps: Double? = nil, maxBenchmarkWriteMBps: Double? = nil, dateAdded: Date = Date(), dateLastSeen: Date = Date()) {
        self.id = id
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.vendorName = vendorName
        self.productName = productName
        self.maxObservedSpeedBps = maxObservedSpeedBps
        self.maxBenchmarkReadMBps = maxBenchmarkReadMBps
        self.maxBenchmarkWriteMBps = maxBenchmarkWriteMBps
        self.dateAdded = dateAdded
        self.dateLastSeen = dateLastSeen
    }

    public func matches(device: DriveDevice) -> Bool {
        guard let v1 = self.vendorID, let v2 = device.vendorID, v1 == v2 else { return false }
        guard let p1 = self.productID, let p2 = device.productID, p1 == p2 else { return false }
        if let s1 = self.serialNumber, let s2 = device.serialNumber {
            return s1 == s2
        }
        return true
    }
}

public struct CableTestResult: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let cableLabel: String
    public let timestamp: Date
    public let deviceName: String
    public let deviceVendorID: Int?
    public let deviceProductID: Int?
    public let deviceSerialNumber: String?
    public let linkSpeedBps: UInt64
    public let benchmarkReadMBps: Double?
    public let benchmarkWriteMBps: Double?
    public let portInfo: String?
    public let hubInfo: String?
    public let userNotes: String?
    public let topologyDescription: String?
    public let connectionFingerprint: String?
    public let cableID: UUID?
    public let category: CableCategory

    private enum CodingKeys: String, CodingKey {
        case id
        case cableLabel
        case timestamp
        case deviceName
        case deviceVendorID
        case deviceProductID
        case deviceSerialNumber
        case linkSpeedBps
        case benchmarkReadMBps
        case benchmarkWriteMBps
        case portInfo
        case hubInfo
        case userNotes
        case topologyDescription
        case connectionFingerprint
        case cableID
        case category
    }

    public init(id: UUID = UUID(), cableLabel: String, timestamp: Date = Date(), deviceName: String, deviceVendorID: Int? = nil, deviceProductID: Int? = nil, deviceSerialNumber: String? = nil, linkSpeedBps: UInt64, benchmarkReadMBps: Double? = nil, benchmarkWriteMBps: Double? = nil, portInfo: String? = nil, hubInfo: String? = nil, userNotes: String? = nil, topologyDescription: String? = nil, connectionFingerprint: String? = nil, cableID: UUID? = nil, category: CableCategory = .data) {
        self.id = id
        self.cableLabel = cableLabel
        self.timestamp = timestamp
        self.deviceName = deviceName
        self.deviceVendorID = deviceVendorID
        self.deviceProductID = deviceProductID
        self.deviceSerialNumber = deviceSerialNumber
        self.linkSpeedBps = linkSpeedBps
        self.benchmarkReadMBps = benchmarkReadMBps
        self.benchmarkWriteMBps = benchmarkWriteMBps
        self.portInfo = portInfo
        self.hubInfo = hubInfo
        self.userNotes = userNotes
        self.topologyDescription = topologyDescription
        self.connectionFingerprint = connectionFingerprint
        self.cableID = cableID
        self.category = category
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        cableLabel = try container.decode(String.self, forKey: .cableLabel)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        deviceVendorID = try container.decodeIfPresent(Int.self, forKey: .deviceVendorID)
        deviceProductID = try container.decodeIfPresent(Int.self, forKey: .deviceProductID)
        deviceSerialNumber = try container.decodeIfPresent(String.self, forKey: .deviceSerialNumber)
        linkSpeedBps = try container.decode(UInt64.self, forKey: .linkSpeedBps)
        benchmarkReadMBps = try container.decodeIfPresent(Double.self, forKey: .benchmarkReadMBps)
        benchmarkWriteMBps = try container.decodeIfPresent(Double.self, forKey: .benchmarkWriteMBps)
        portInfo = try container.decodeIfPresent(String.self, forKey: .portInfo)
        hubInfo = try container.decodeIfPresent(String.self, forKey: .hubInfo)
        userNotes = try container.decodeIfPresent(String.self, forKey: .userNotes)
        topologyDescription = try container.decodeIfPresent(String.self, forKey: .topologyDescription)
        connectionFingerprint = try container.decodeIfPresent(String.self, forKey: .connectionFingerprint)
        cableID = try container.decodeIfPresent(UUID.self, forKey: .cableID)
        category = try container.decodeIfPresent(CableCategory.self, forKey: .category) ?? .data
    }

    public var linkSpeedFormatted: String {
        formatSpeed(bps: linkSpeedBps)
    }

    public var rating: LinkSpeedRating {
        LinkSpeedRating.from(speedBps: linkSpeedBps)
    }

    public var usbRating: LinkSpeedRating? { category == .data ? rating : nil }

    public var primaryMeasurement: ConnectionMeasurement {
        switch category {
        case .data: .usbLink(bps: linkSpeedBps)
        case .video: .videoRequirement(bps: linkSpeedBps)
        case .charging: .charging(watts: Double(linkSpeedBps) / 1_000_000)
        }
    }
}

public struct CableStabilityAnalysis: Sendable, Hashable, Codable {
    public let cableLabel: String
    public let results: [CableTestResult]

    public init(cableLabel: String, results: [CableTestResult]) {
        self.cableLabel = cableLabel
        self.results = results
    }

    public var isStable: Bool {
        guard !results.isEmpty else { return true }
        let firstRating = results[0].rating
        return results.allSatisfy { $0.rating == firstRating }
    }

    public var dominantSpeed: UInt64? {
        let speeds = results.map { $0.linkSpeedBps }
        let counts = speeds.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    public var warningMessage: String? {
        isStable ? nil : "⚠️ CONNESSIONE INSTABILE"
    }
}

public struct BenchmarkConfig: Sendable, Hashable, Codable {
    public let testSizeBytes: UInt64

    public init(testSizeBytes: UInt64) {
        self.testSizeBytes = testSizeBytes
    }

    public static let presets: [BenchmarkConfig] = [
        BenchmarkConfig(testSizeBytes: 1_000_000_000),
        BenchmarkConfig(testSizeBytes: 2_000_000_000),
        BenchmarkConfig(testSizeBytes: 5_000_000_000),
        BenchmarkConfig(testSizeBytes: 10_000_000_000)
    ]

    public var testSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(testSizeBytes), countStyle: .file)
    }
}

public struct BenchmarkResult: Codable, Hashable, Sendable {
    public let sequentialReadMBps: Double
    public let sequentialWriteMBps: Double
    public let randomReadIOPS: Double?
    public let randomWriteIOPS: Double?
    public let testSizeBytes: UInt64
    public let timestamp: Date
    public let durationSeconds: Double

    public init(sequentialReadMBps: Double, sequentialWriteMBps: Double, randomReadIOPS: Double? = nil, randomWriteIOPS: Double? = nil, testSizeBytes: UInt64, timestamp: Date = Date(), durationSeconds: Double) {
        self.sequentialReadMBps = sequentialReadMBps
        self.sequentialWriteMBps = sequentialWriteMBps
        self.randomReadIOPS = randomReadIOPS
        self.randomWriteIOPS = randomWriteIOPS
        self.testSizeBytes = testSizeBytes
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
    }
}

public struct AdvancedBenchmarkRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let connectionFingerprint: String
    public let deviceName: String
    public let result: AdvancedBenchmarkResult

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        connectionFingerprint: String,
        deviceName: String,
        result: AdvancedBenchmarkResult
    ) {
        self.id = id
        self.timestamp = timestamp
        self.connectionFingerprint = connectionFingerprint
        self.deviceName = deviceName
        self.result = result
    }
}

// MARK: - HDMI Models

public struct DiagnosisWizardStep: Codable, Hashable, Sendable {
    public let name: String
    public let passed: Bool
    public let resultDescription: String
    public init(name: String, passed: Bool, resultDescription: String) {
        self.name = name
        self.passed = passed
        self.resultDescription = resultDescription
    }
}

extension HDMIChainDiagnosis {
    public var wizardSteps: [DiagnosisWizardStep] {
        return []
    }
    public var finalVerdict: String? {
        return self.explanation
    }
    public var naturalLanguageExplanation: String {
        return self.explanation
    }
}

public struct HDMICompatibilityRow: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let resolution: String
    public let refreshRate: String
    public let status: HDMICapabilityTestStatus
    
    public init(id: UUID = UUID(), resolution: String, refreshRate: String, status: HDMICapabilityTestStatus) {
        self.id = id
        self.resolution = resolution
        self.refreshRate = refreshRate
        self.status = status
    }
}
