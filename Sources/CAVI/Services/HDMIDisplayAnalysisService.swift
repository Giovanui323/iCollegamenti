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
    private var analyzedDisplayID: CGDirectDisplayID?
    
    public init() {}
    
    public func analyze(displayID: CGDirectDisplayID, edid: CAVICore.ParsedEDID?) {
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return }
        
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        if let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] {
            self.allSupportedModes = modes
        }
        
        // `width`/`height` are points; on a HiDPI mode the link carries the pixel size.
        let width = mode.pixelWidth
        let height = mode.pixelHeight
        var refreshRate = mode.refreshRate
        
        var isHDR = false
        var bitDepth = 8
        if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID }) {
            // Some displays report 0 Hz in their mode; the screen still knows its frame rate.
            if refreshRate == 0 { refreshRate = Double(screen.maximumFramesPerSecond) }
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
            transportType: detectTransport(displayID: displayID),
            bandwidthRequirement: calc
        )
        self.currentSignal = config
        self.analyzedDisplayID = displayID
        
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
    
    /// Physical link as reported by macOS's DisplayPort transport, not assumed to be HDMI.
    public func detectTransport(displayID: CGDirectDisplayID) -> String {
        let externalCount = NSScreen.screens.compactMap {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        }.filter { CGDisplayIsBuiltin($0) == 0 }.count
        let match = DisplayLinkMatcher.observation(
            for: (Int(CGDisplayModelNumber(displayID)), Int(CGDisplaySerialNumber(displayID)), nil),
            in: DisplayPortTransportReader.observations(),
            externalDisplayCount: externalCount
        )
        guard let match else { return "Unknown" }
        switch DisplayLinkClassifier.kind(for: match) {
        case .builtInHDMIPort, .usbCToHDMIAdapter: return "HDMI"
        case .usbCDisplayPortAltMode: return "DisplayPort"
        case .thunderboltOrUSB4Tunnel: return "Thunderbolt/USB4"
        case .unknown: return "Unknown"
        }
    }
    
    public func currentConfiguration(for displayID: CGDirectDisplayID) -> HDMISignalConfiguration? {
        // The cached signal belongs to the last analysed display only.
        analyzedDisplayID == displayID ? currentSignal : nil
    }
    
    public func currentDiagnosis(for displayID: CGDirectDisplayID) -> HDMIChainDiagnosis? {
        return nil
    }
}
