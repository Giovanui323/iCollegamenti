import Foundation

public enum HDMITestPattern: String, Codable, Hashable, Sendable, CaseIterable {
    case pixelGrid
    case chromaCheck
    case gradient
    case colorBars
    case blackLevel
    case whiteLevel
    case overscan
    case sharpness
    case hdrHighlight
    case frameTiming
    
    public var title: String {
        return self.rawValue
    }
    
    public var description: String {
        return self.rawValue
    }
}
