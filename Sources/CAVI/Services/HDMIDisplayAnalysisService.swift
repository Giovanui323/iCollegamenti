import Foundation
import CoreGraphics
import AppKit
import CAVICore

public struct HDMIAudioDevice: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let sampleRate: Double
    public let channels: Int
    public let isActive: Bool
    
    public init(id: String, name: String, sampleRate: Double, channels: Int, isActive: Bool) {
        self.id = id
        self.name = name
        self.sampleRate = sampleRate
        self.channels = channels
        self.isActive = isActive
    }
}

@Observable
@MainActor
public final class HDMIDisplayAnalysisService {
    public private(set) var currentSignal: HDMISignalConfiguration?
    public private(set) var allSupportedModes: [CGDisplayMode] = []
    public private(set) var hdmiAudioDevices: [HDMIAudioDevice] = []
    public private(set) var connectionTransport: String = "Unknown"
    public private(set) var fallbackDetection: HDMIFallbackDetection?
    
    public init() {}
    
    public func analyze(displayID: CGDirectDisplayID, edid: CAVICore.ParsedEDID?) {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return }
        
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        if let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] {
            self.allSupportedModes = modes
        }
        
        let width = mode.width
        let height = mode.height
        let refreshRate = mode.refreshRate
        
        var isHDR = false
        var bitDepth = 8
        if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID }) {
            isHDR = screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0
            if isHDR || screen.depth == .sixtyfourBitRGB { bitDepth = 10 }
        }
        
        var calc = HDMIBandwidthCalculator.calculate(width: width, height: height, refreshRate: refreshRate, bitDepth: bitDepth, chroma: .rgb444, isDSC: false)
        var chroma = ChromaSubsampling.rgb444
        
        if calc.totalBandwidthGbps > 18.0 {
            chroma = .ycbcr420
            calc = HDMIBandwidthCalculator.calculate(width: width, height: height, refreshRate: refreshRate, bitDepth: bitDepth, chroma: chroma, isDSC: false)
        }
        
        let config = HDMISignalConfiguration(
            width: width,
            height: height,
            refreshRate: refreshRate,
            bitDepth: bitDepth,
            chroma: chroma,
            isHDRActive: isHDR,
            isDSCActive: false,
            isVRRActive: false,
            transportType: "HDMI",
            bandwidthRequirement: calc
        )
        self.currentSignal = config
        
        self.fallbackDetection = nil
        if let edid = edid {
            if let nativeRes = edid.nativeResolution, (nativeRes.width > width || nativeRes.height > height) {
                self.fallbackDetection = HDMIFallbackDetection(
                    requested: nil,
                    actual: config,
                    isFallback: true,
                    fallbackReasons: ["Native resolution higher than current mode"]
                )
            }
        }
        
        self.connectionTransport = detectTransport(displayID: displayID)
    }
    
    public func detectTransport(displayID: CGDirectDisplayID) -> String {
        return "HDMI"
    }
    
    public func currentConfiguration(for displayID: CGDirectDisplayID) -> HDMISignalConfiguration? {
        return currentSignal
    }
    
    public func currentDiagnosis(for displayID: CGDirectDisplayID) -> HDMIChainDiagnosis? {
        return nil
    }
}
