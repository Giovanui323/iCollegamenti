import Foundation

public struct HDMIConnectionScore: Codable, Hashable, Sendable {
    public let overall: Int
    public let level: HDMIScoreLevel
    public let bandwidth: Int
    public let signalConfig: Int
    public let stability: Int
    public let hdr: Int
    public let audio: Int
    public let handshake: Int
}

public enum HDMIScoreLevel: String, Codable, Hashable, Sendable {
    case excellent, good, adequate, poor, critical
}

public struct HDMIGamingScore: Codable, Hashable, Sendable {
    public let overall: Int
    public let supports4K120: Bool
    public let supportsHighRefresh: Bool
    public let supportsVRR: Bool
    public let supportsHDR: Bool
    public let chromaQuality: String
    public let bitDepth: Int?
    public let stabilityScore: Int
}

public struct HDMIProfessionalScore: Codable, Hashable, Sendable {
    public let overall: Int
    public let rgbFull: Bool
    public let is10Bit: Bool
    public let supportsHDR: Bool
    public let maxResolution: String
    public let maxRefresh: String
    public let isCompressed: Bool
    public let edidComplete: Bool
}

public enum HDMIScoringEngine {
    public static func connectionScore(
        bandwidthHeadroom: BandwidthHeadroom,
        stabilityScore: Int,
        isHDR: Bool,
        audioFormats: [CTAAudioFormat],
        disconnects: Int
    ) -> HDMIConnectionScore {
        let bandwidth = min(100, Int(bandwidthHeadroom.headroomPercent * 2.5) + 50)
        let signal = isHDR ? 100 : 80
        let stability = max(0, 100 - disconnects * 20)
        let hdr = isHDR ? 100 : 0
        let audio = audioFormats.isEmpty ? 50 : min(100, audioFormats.count * 15 + 40)
        let handshake = max(0, 100 - disconnects * 15)
        let overall = (bandwidth + signal + stability + hdr + audio + handshake) / 6
        let level: HDMIScoreLevel = overall >= 90 ? .excellent : overall >= 75 ? .good : overall >= 50 ? .adequate : overall >= 25 ? .poor : .critical
        return HDMIConnectionScore(overall: overall, level: level, bandwidth: bandwidth, signalConfig: signal, stability: stability, hdr: hdr, audio: audio, handshake: handshake)
    }
    
    public static func connectionScore(overall: Int = 100) -> HDMIConnectionScore {
        return HDMIConnectionScore(overall: overall, level: .excellent, bandwidth: 100, signalConfig: 100, stability: 100, hdr: 100, audio: 100, handshake: 100)
    }
    
    public static func gamingScore(
        supports4K120: Bool, supportsVRR: Bool, supportsHDR: Bool,
        chromaQuality: ChromaSubsampling, bitDepth: Int, stabilityScore: Int
    ) -> HDMIGamingScore {
        var score = 0
        if supports4K120 { score += 25 }
        if supportsVRR { score += 20 }
        if supportsHDR { score += 20 }
        if chromaQuality == .rgb444 || chromaQuality == .ycbcr444 { score += 15 }
        if bitDepth >= 10 { score += 10 }
        score += stabilityScore / 10
        return HDMIGamingScore(overall: min(100, score), supports4K120: supports4K120, supportsHighRefresh: supports4K120, supportsVRR: supportsVRR, supportsHDR: supportsHDR, chromaQuality: chromaQuality.rawValue, bitDepth: bitDepth, stabilityScore: stabilityScore)
    }
    
    public static func gamingScore(overall: Int = 100) -> HDMIGamingScore {
        return HDMIGamingScore(overall: overall, supports4K120: true, supportsHighRefresh: true, supportsVRR: true, supportsHDR: true, chromaQuality: "RGB 4:4:4", bitDepth: 10, stabilityScore: 100)
    }

    public static func professionalScore(
        rgbFull: Bool, is10Bit: Bool, supportsHDR: Bool,
        maxResolution: String, maxRefresh: String,
        isCompressed: Bool, edidComplete: Bool
    ) -> HDMIProfessionalScore {
        var score = 0
        if rgbFull { score += 20 }
        if is10Bit { score += 20 }
        if supportsHDR { score += 20 }
        if !isCompressed { score += 20 }
        if edidComplete { score += 20 }
        return HDMIProfessionalScore(overall: min(100, score), rgbFull: rgbFull, is10Bit: is10Bit, supportsHDR: supportsHDR, maxResolution: maxResolution, maxRefresh: maxRefresh, isCompressed: isCompressed, edidComplete: edidComplete)
    }
    
    public static func professionalScore(overall: Int = 100) -> HDMIProfessionalScore {
        return HDMIProfessionalScore(overall: overall, rgbFull: true, is10Bit: true, supportsHDR: true, maxResolution: "8K", maxRefresh: "120Hz", isCompressed: false, edidComplete: true)
    }
}
