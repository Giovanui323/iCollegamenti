import Foundation

// MARK: - Severity Enum

public enum Severity: String, Sendable, Codable, Hashable {
    case none
    case warning
    case critical
}

// MARK: - Cable Assessment

public struct CableAssessment: Sendable {
    public let rating: LinkSpeedRating
    public let isBottleneck: Bool
    public let headline: String
    public let bottleneckMessage: String?
    public let possibleCauses: [String]
}

// MARK: - LinkSpeedService

public enum LinkSpeedService {
    
    public static func classify(speedBps: UInt64?) -> LinkSpeedRating {
        return LinkSpeedRating.from(speedBps: speedBps)
    }
    
    public static func formatSpeed(_ bps: UInt64) -> String {
        if bps >= 1_000_000_000 {
            let gbps = Double(bps) / 1_000_000_000.0
            if gbps.truncatingRemainder(dividingBy: 1.0) == 0 {
                return String(format: "%.0f Gb/s", gbps)
            } else {
                return String(format: "%.1f Gb/s", gbps)
            }
        } else if bps >= 1_000_000 {
            let mbps = Double(bps) / 1_000_000.0
            return String(format: "%.0f Mb/s", mbps)
        } else {
            return "\(bps) bps"
        }
    }
    
    /// Generates a conservative assessment. The fallback is intentionally not
    /// a cable verdict: macOS observes the resulting link, not every physical
    /// component responsible for it.
    public static func generateCableAssessment(currentSpeed: UInt64?, referenceMaxSpeed: UInt64?) -> CableAssessment {
        let rating = classify(speedBps: currentSpeed)
        let formattedCurrent = currentSpeed != nil ? formatSpeed(currentSpeed!) : "sconosciuta"
        
        let headline = "La connessione con il dispositivo utilizzato è stata negoziata a \(formattedCurrent)."
        
        var isBottleneck = false
        var bottleneckMessage: String? = nil
        var causes: [String] = []
        
        if let current = currentSpeed, let reference = referenceMaxSpeed, current < reference {
            isBottleneck = true
            let formattedRef = formatSpeed(reference)
            bottleneckMessage = "Il dispositivo è stato precedentemente rilevato a \(formattedRef), mentre la connessione attuale è negoziata a \(formattedCurrent). macOS non può attribuire la differenza al solo cavo."
            
            if current <= 480_000_000 {
                causes = [
                    "Cavo, hub o adattatore intermedio limitato a USB 2.0",
                    "Fallback del collegamento a USB 2.0",
                    "Porta o interfaccia incompatibile",
                    "Problema di negoziazione"
                ]
            } else {
                causes = [
                    "Cavo, hub o adattatore intermedio nella catena",
                    "Porta del computer o del dispositivo",
                    "Problema di negoziazione"
                ]
            }
        }
        
        return CableAssessment(
            rating: rating,
            isBottleneck: isBottleneck,
            headline: headline,
            bottleneckMessage: bottleneckMessage,
            possibleCauses: causes
        )
    }
}
