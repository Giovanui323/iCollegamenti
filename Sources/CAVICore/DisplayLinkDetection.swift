import Foundation

// MARK: - Raw observation

/// What macOS reports for one DisplayPort transport (`IOPortTransportStateDisplayPort`).
/// On Apple silicon every external display — built-in HDMI port, USB-C Alt Mode or a
/// Thunderbolt/USB4 tunnel — is driven through one of these, so it is the ground truth
/// for the physical port, the negotiated link rate and the lane count.
public struct DisplayPortTransportObservation: Codable, Hashable, Sendable {
    /// Physical port the transport belongs to, e.g. "HDMI" or "USB-C".
    public let portTypeDescription: String?
    public let portNumber: Int?
    public let isActive: Bool
    public let isHotPlugHigh: Bool
    /// True when the DisplayPort stream travels inside a Thunderbolt/USB4 tunnel.
    public let isTunneled: Bool
    /// Per-lane signalling rate actually negotiated, in Hz (= bit/s per lane).
    public let laneRateHz: UInt64?
    public let linkRateDescription: String?
    public let laneCount: Int?
    public let maxLaneCount: Int?
    /// Type of the downstream-facing port of a branch device (protocol converter),
    /// e.g. "HDMI" for a USB-C → HDMI adapter or the Mac's own HDMI converter.
    public let downstreamPortTypeDescription: String?
    public let productName: String?
    public let productID: Int?
    public let serialNumber: Int?
    public let manufacturerCode: String?

    public init(
        portTypeDescription: String?,
        portNumber: Int? = nil,
        isActive: Bool,
        isHotPlugHigh: Bool,
        isTunneled: Bool,
        laneRateHz: UInt64?,
        linkRateDescription: String? = nil,
        laneCount: Int?,
        maxLaneCount: Int? = nil,
        downstreamPortTypeDescription: String? = nil,
        productName: String? = nil,
        productID: Int? = nil,
        serialNumber: Int? = nil,
        manufacturerCode: String? = nil
    ) {
        self.portTypeDescription = portTypeDescription
        self.portNumber = portNumber
        self.isActive = isActive
        self.isHotPlugHigh = isHotPlugHigh
        self.isTunneled = isTunneled
        self.laneRateHz = laneRateHz
        self.linkRateDescription = linkRateDescription
        self.laneCount = laneCount
        self.maxLaneCount = maxLaneCount
        self.downstreamPortTypeDescription = downstreamPortTypeDescription
        self.productName = productName
        self.productID = productID
        self.serialNumber = serialNumber
        self.manufacturerCode = manufacturerCode
    }

    /// A transport only describes a live link when it is active and the sink asserts hot-plug.
    public var isLive: Bool { isActive && isHotPlugHigh }
}

// MARK: - Classification

public enum DisplayConnectionKind: String, Codable, Hashable, Sendable {
    /// The Mac's own HDMI port (internally a DisplayPort → HDMI converter).
    case builtInHDMIPort
    /// USB-C port in DisplayPort Alt Mode with a DisplayPort sink (USB-C → DP cable, or a DP monitor on USB-C).
    case usbCDisplayPortAltMode
    /// USB-C port in DisplayPort Alt Mode feeding an HDMI converter (USB-C → HDMI adapter/cable).
    case usbCToHDMIAdapter
    /// DisplayPort tunnelled through Thunderbolt / USB4 (dock, TB display).
    case thunderboltOrUSB4Tunnel
    case unknown

    public var italianDescription: String {
        switch self {
        case .builtInHDMIPort: return "Porta HDMI del Mac"
        case .usbCDisplayPortAltMode: return "USB-C → DisplayPort (Alt Mode)"
        case .usbCToHDMIAdapter: return "USB-C → HDMI (adattatore Alt Mode)"
        case .thunderboltOrUSB4Tunnel: return "DisplayPort su Thunderbolt/USB4"
        case .unknown: return "Collegamento video non identificato"
        }
    }

    public var englishDescription: String {
        switch self {
        case .builtInHDMIPort: return "Mac HDMI port"
        case .usbCDisplayPortAltMode: return "USB-C → DisplayPort (Alt Mode)"
        case .usbCToHDMIAdapter: return "USB-C → HDMI (Alt Mode adapter)"
        case .thunderboltOrUSB4Tunnel: return "DisplayPort over Thunderbolt/USB4"
        case .unknown: return "Unidentified video link"
        }
    }

    /// True when the cable itself carries a DisplayPort signal end to end.
    public var isDisplayPortCable: Bool { self == .usbCDisplayPortAltMode }
}

/// The DisplayPort link as negotiated, with the payload it can actually carry.
public struct DisplayLinkAssessment: Codable, Hashable, Sendable {
    public let kind: DisplayConnectionKind
    /// DP generation name for the negotiated lane rate (RBR, HBR, HBR2, HBR3, UHBR10…).
    public let generation: String?
    public let laneRateGbps: Double?
    public let laneCount: Int?
    public let maxLaneCount: Int?
    /// Lane rate × lanes.
    public let rawGbps: Double?
    /// Payload after line coding (8b/10b up to HBR3, 128b/132b for UHBR).
    public let effectiveGbps: Double?
    public let productName: String?
    public let portNumber: Int?

    public init(kind: DisplayConnectionKind, generation: String?, laneRateGbps: Double?, laneCount: Int?, maxLaneCount: Int?, rawGbps: Double?, effectiveGbps: Double?, productName: String?, portNumber: Int?) {
        self.kind = kind
        self.generation = generation
        self.laneRateGbps = laneRateGbps
        self.laneCount = laneCount
        self.maxLaneCount = maxLaneCount
        self.rawGbps = rawGbps
        self.effectiveGbps = effectiveGbps
        self.productName = productName
        self.portNumber = portNumber
    }

    /// True when fewer lanes were trained than the link supports (typical of a
    /// USB-C dock sharing the connector with USB 3, or of a marginal cable).
    public var isLaneReduced: Bool {
        guard let laneCount, let maxLaneCount else { return false }
        return laneCount < maxLaneCount
    }

    /// e.g. "USB-C → DisplayPort (Alt Mode) · HBR3 8.1 Gb/s × 4 lane (25.9 Gb/s utili)".
    public func summary(italian: Bool) -> String {
        var text = italian ? kind.italianDescription : kind.englishDescription
        if let laneRateGbps, let laneCount {
            let gen = generation.map { "\($0) " } ?? ""
            text += " · \(gen)\(Self.format(laneRateGbps)) Gb/s × \(laneCount) lane"
            if let effectiveGbps {
                text += italian ? " (\(Self.format(effectiveGbps)) Gb/s utili)" : " (\(Self.format(effectiveGbps)) Gb/s usable)"
            }
        }
        return text
    }

    static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}

public enum DisplayLinkClassifier {
    public static func kind(for observation: DisplayPortTransportObservation) -> DisplayConnectionKind {
        let port = observation.portTypeDescription?.lowercased() ?? ""
        if observation.isTunneled { return .thunderboltOrUSB4Tunnel }
        if port.contains("hdmi") { return .builtInHDMIPort }
        if port.contains("usb-c") || port.contains("usbc") || port.contains("thunderbolt") {
            let downstream = observation.downstreamPortTypeDescription?.lowercased() ?? ""
            return downstream.contains("hdmi") ? .usbCToHDMIAdapter : .usbCDisplayPortAltMode
        }
        return .unknown
    }

    public static func assess(_ observation: DisplayPortTransportObservation) -> DisplayLinkAssessment {
        let laneRateGbps = observation.laneRateHz.map { Double($0) / 1_000_000_000 }
            ?? observation.linkRateDescription.flatMap(laneRate(fromDescription:))
        let lanes = observation.laneCount.flatMap { $0 > 0 ? $0 : nil }
        let raw = laneRateGbps.flatMap { rate in lanes.map { rate * Double($0) } }
        let effective = laneRateGbps.flatMap { rate in raw.map { $0 * codingEfficiency(laneRateGbps: rate) } }
        return DisplayLinkAssessment(
            kind: kind(for: observation),
            generation: laneRateGbps.flatMap(generation(laneRateGbps:)),
            laneRateGbps: laneRateGbps,
            laneCount: lanes,
            maxLaneCount: observation.maxLaneCount,
            rawGbps: raw,
            effectiveGbps: effective,
            productName: observation.productName,
            portNumber: observation.portNumber
        )
    }

    /// 8b/10b for RBR…HBR3, 128b/132b for UHBR rates.
    public static func codingEfficiency(laneRateGbps: Double) -> Double {
        laneRateGbps >= 10 ? 128.0 / 132.0 : 0.8
    }

    public static func generation(laneRateGbps rate: Double) -> String? {
        let table: [(Double, String)] = [(1.62, "RBR"), (2.7, "HBR"), (5.4, "HBR2"), (8.1, "HBR3"),
                                         (10, "UHBR10"), (13.5, "UHBR13.5"), (20, "UHBR20")]
        return table.first { abs($0.0 - rate) < 0.05 }?.1
    }

    /// Parses "8.1 Gbps (HBR3)" style descriptions.
    static func laneRate(fromDescription text: String) -> Double? {
        let number = text.prefix { $0.isNumber || $0 == "." }
        return Double(number)
    }
}

// MARK: - Matching a transport to a CoreGraphics display

public enum DisplayLinkMatcher {
    /// Picks the live transport that drives a display. EDID product code and serial are
    /// matched first (exact), then the product name; a lone live transport is used only
    /// when there is exactly one external display, so links are never swapped.
    public static func observation(
        for display: (modelNumber: Int?, serialNumber: Int?, name: String?),
        in observations: [DisplayPortTransportObservation],
        externalDisplayCount: Int
    ) -> DisplayPortTransportObservation? {
        let live = observations.filter(\.isLive)
        if let model = display.modelNumber, model != 0 {
            let byModel = live.filter { $0.productID == model }
            if let serial = display.serialNumber, serial != 0,
               let exact = byModel.first(where: { $0.serialNumber == serial }) {
                return exact
            }
            if byModel.count == 1 { return byModel[0] }
        }
        if let name = display.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            let byName = live.filter { $0.productName?.caseInsensitiveCompare(name) == .orderedSame }
            if byName.count == 1 { return byName[0] }
        }
        if externalDisplayCount == 1, live.count == 1 { return live[0] }
        return nil
    }
}

// MARK: - USB Billboard (Alt Mode) devices

/// A USB-C cable or adapter that uses an Alternate Mode (almost always DisplayPort)
/// exposes a USB *Billboard* device (class 0x11). It is not a data peripheral: it only
/// advertises the Alt Modes the accessory supports. By the USB-C specification it must
/// appear when Alt Mode could not be entered, and many adapters keep it visible anyway,
/// so its presence identifies a video accessory but not, by itself, a working link.
public enum USBBillboardPolicy {
    public static let billboardDeviceClass = 0x11

    public static func isBillboard(deviceClass: Int?, productName: String?) -> Bool {
        if deviceClass == billboardDeviceClass { return true }
        return productName?.localizedCaseInsensitiveContains("billboard") ?? false
    }

    /// Reads a `bDeviceClass` value as recorded in technical properties ("17", "0x11").
    public static func deviceClass(fromPropertyValue value: String?) -> Int? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        if value.lowercased().hasPrefix("0x") { return Int(value.dropFirst(2), radix: 16) }
        return Int(value)
    }

    /// History label for a Billboard accessory, enriched with the live DP link when one exists.
    public static func historyLabel(liveLink: DisplayLinkAssessment?) -> String {
        guard let liveLink, liveLink.kind != .builtInHDMIPort else {
            return "Cavo/adattatore USB-C video (Alt Mode)"
        }
        return "Cavo \(liveLink.kind.italianDescription)"
    }
}
