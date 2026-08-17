import Foundation

public struct HDMICompatibilityRow: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let modeLabel: String
    public let width: Int
    public let height: Int  
    public let refreshRate: Double
    public let bitDepth: Int
    public let chroma: ChromaSubsampling
    public let isHDR: Bool
    public let requiredBandwidthGbps: Double
    public let result: HDMICapabilityTestStatus
}

public enum HDMICompatibilityMatrixGenerator {
    public static func standardModes() -> [HDMICompatibilityRow] {
        let modes: [(String, Int, Int, Double, Int, ChromaSubsampling, Bool)] = [
            ("1080p 60Hz SDR", 1920, 1080, 60, 8, .rgb444, false),
            ("1080p 120Hz SDR", 1920, 1080, 120, 8, .rgb444, false),
            ("1440p 60Hz SDR", 2560, 1440, 60, 8, .rgb444, false),
            ("1440p 120Hz SDR", 2560, 1440, 120, 8, .rgb444, false),
            ("4K 30Hz SDR", 3840, 2160, 30, 8, .rgb444, false),
            ("4K 60Hz SDR", 3840, 2160, 60, 8, .rgb444, false),
            ("4K 60Hz HDR", 3840, 2160, 60, 10, .rgb444, true),
            ("4K 60Hz HDR 4:2:0", 3840, 2160, 60, 10, .ycbcr420, true),
            ("4K 120Hz SDR", 3840, 2160, 120, 8, .rgb444, false),
            ("4K 120Hz HDR", 3840, 2160, 120, 10, .rgb444, true),
            ("4K 120Hz HDR 4:2:2", 3840, 2160, 120, 10, .ycbcr422, true),
            ("5K 60Hz SDR", 5120, 2880, 60, 8, .rgb444, false),
            ("8K 30Hz SDR", 7680, 4320, 30, 8, .rgb444, false),
            ("8K 60Hz SDR", 7680, 4320, 60, 8, .ycbcr420, false),
        ]
        return modes.map { mode in
            // Approximation for bandwidth for the sake of the stub
            let pixelsPerSecond = Double(mode.1 * mode.2) * mode.3
            let bpp = Double(mode.4 * 3)
            let bandwidth = (pixelsPerSecond * bpp) / 1_000_000_000.0 * 1.2
            return HDMICompatibilityRow(
                id: UUID(),
                modeLabel: mode.0,
                width: mode.1,
                height: mode.2,
                refreshRate: mode.3,
                bitDepth: mode.4,
                chroma: mode.5,
                isHDR: mode.6,
                requiredBandwidthGbps: bandwidth,
                result: .untested
            )
        }
    }
    public static func updateResult(matrix: inout [HDMICompatibilityRow], modeID: UUID, result: HDMICapabilityTestStatus) {
        if let index = matrix.firstIndex(where: { $0.id == modeID }) {
            let old = matrix[index]
            matrix[index] = HDMICompatibilityRow(
                id: old.id,
                modeLabel: old.modeLabel,
                width: old.width,
                height: old.height,
                refreshRate: old.refreshRate,
                bitDepth: old.bitDepth,
                chroma: old.chroma,
                isHDR: old.isHDR,
                requiredBandwidthGbps: old.requiredBandwidthGbps,
                result: result
            )
        }
    }
}
