import Foundation

public enum ChromaSubsampling: String, Codable, Hashable, Sendable, CaseIterable {
    case rgb444 = "RGB 4:4:4"
    case ycbcr444 = "YCbCr 4:4:4"
    case ycbcr422 = "YCbCr 4:2:2"
    case ycbcr420 = "YCbCr 4:2:0"
    
    public var bandwidthMultiplier: Double {
        switch self {
        case .rgb444, .ycbcr444: return 3.0
        case .ycbcr422: return 2.0
        case .ycbcr420: return 1.5
        }
    }
    
    public var description: String {
        return self.rawValue
    }
}

public struct HDMIBandwidthRequirement: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let refreshRate: Double
    public let bitDepth: Int
    public let chroma: ChromaSubsampling
    public let isDSCActive: Bool
    public let rawBandwidthGbps: Double
    public let totalBandwidthGbps: Double
    public let dscBandwidthGbps: Double?
    public let effectiveBandwidthGbps: Double
}

public struct BandwidthHeadroom: Codable, Hashable, Sendable {
    public let requiredGbps: Double
    public let availableGbps: Double
    public let headroomPercent: Double
    public let headroomLevel: HeadroomLevel
}

public enum HeadroomLevel: String, Codable, Hashable, Sendable {
    case comfortable
    case adequate
    case tight
    case critical
    case exceeded
}

public enum HDMIStandard: String, Codable, Hashable, Sendable, CaseIterable {
    case hdmi14 = "HDMI 1.4"
    case hdmi20 = "HDMI 2.0"
    case hdmi21 = "HDMI 2.1"
    case dp14 = "DisplayPort 1.4"
    case dp21 = "DisplayPort 2.1"
    
    public var maxBandwidthGbps: Double {
        switch self {
        case .hdmi14: return 10.2
        case .hdmi20: return 18.0
        case .hdmi21: return 48.0
        case .dp14: return 32.4
        case .dp21: return 80.0
        }
    }
}

public enum HDMIBandwidthCalculator {
    public static func calculate(width: Int, height: Int, refreshRate: Double, bitDepth: Int, chroma: ChromaSubsampling, isDSC: Bool) -> HDMIBandwidthRequirement {
        let rawBandwidthbps = Double(width * height) * refreshRate * Double(bitDepth) * chroma.bandwidthMultiplier
        let rawBandwidthGbps = rawBandwidthbps / 1_000_000_000.0
        let totalBandwidthGbps = rawBandwidthGbps * 1.25 // TMDS overhead
        let dscBandwidthGbps = isDSC ? totalBandwidthGbps / 3.0 : nil
        let effective = isDSC ? (dscBandwidthGbps ?? totalBandwidthGbps) : totalBandwidthGbps
        
        return HDMIBandwidthRequirement(
            width: width,
            height: height,
            refreshRate: refreshRate,
            bitDepth: bitDepth,
            chroma: chroma,
            isDSCActive: isDSC,
            rawBandwidthGbps: rawBandwidthGbps,
            totalBandwidthGbps: totalBandwidthGbps,
            dscBandwidthGbps: dscBandwidthGbps,
            effectiveBandwidthGbps: effective
        )
    }
    
    public static func headroom(required: Double, available: Double) -> BandwidthHeadroom {
        let headroomPercent = ((available - required) / required) * 100.0
        let level: HeadroomLevel
        if headroomPercent > 20.0 {
            level = .comfortable
        } else if headroomPercent >= 10.0 {
            level = .adequate
        } else if headroomPercent >= 5.0 {
            level = .tight
        } else if headroomPercent >= 0.0 {
            level = .critical
        } else {
            level = .exceeded
        }
        return BandwidthHeadroom(requiredGbps: required, availableGbps: available, headroomPercent: headroomPercent, headroomLevel: level)
    }
    
    public static func minimumStandard(for requirement: HDMIBandwidthRequirement) -> HDMIStandard {
        let gbps = requirement.effectiveBandwidthGbps
        if gbps <= HDMIStandard.hdmi14.maxBandwidthGbps { return .hdmi14 }
        if gbps <= HDMIStandard.hdmi20.maxBandwidthGbps { return .hdmi20 }
        if gbps <= HDMIStandard.dp14.maxBandwidthGbps { return .dp14 }
        if gbps <= HDMIStandard.hdmi21.maxBandwidthGbps { return .hdmi21 }
        return .dp21
    }
    
    public static func maximumMode(within bandwidthGbps: Double, modes: [HDMIBandwidthRequirement]) -> HDMIBandwidthRequirement? {
        return modes.filter { $0.effectiveBandwidthGbps <= bandwidthGbps }
                    .max { $0.effectiveBandwidthGbps < $1.effectiveBandwidthGbps }
    }
}
