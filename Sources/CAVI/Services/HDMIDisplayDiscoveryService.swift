import Foundation
import SwiftUI
import AppKit
import CoreGraphics
import CAVICore

/// Discovers connected external HDMI / DisplayPort / USB-C displays.
/// Analyzes the active video signal and estimates the minimum connection capability it requires.
@Observable
@MainActor
public final class HDMIDisplayDiscoveryService {
    public var externalDisplays: [HDMIDisplayDevice] = []
    public var selectedDisplay: HDMIDisplayDevice?
    public var selectedDisplayID: CGDirectDisplayID?
    private var isMonitoring = false
    private var refreshTask: Task<Void, Never>?
    private weak var edidReader: EDIDReaderService?
    
    public init() {
    }

    func attachEDIDReader(_ reader: EDIDReaderService) {
        edidReader = reader
    }
    
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        registerDisplayReconfigurationCallback()
        refreshDisplays()
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        CGDisplayRemoveReconfigurationCallback(Self.displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        refreshTask?.cancel()
        refreshTask = nil
        isMonitoring = false
    }
    
    public func refreshDisplays() {
        var activeDisplayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        
        let err = CGGetActiveDisplayList(16, &activeDisplayIDs, &displayCount)
        guard err == .success else { return }
        
        var detected: [HDMIDisplayDevice] = []
        let transports = DisplayPortTransportReader.observations()
        let externalCount = (0..<Int(displayCount)).filter { CGDisplayIsBuiltin(activeDisplayIDs[$0]) == 0 }.count
        
        for i in 0..<Int(displayCount) {
            let displayID = activeDisplayIDs[i]
            
            // Skip built-in MacBook screen
            if CGDisplayIsBuiltin(displayID) != 0 {
                continue
            }
            
            // Get screen resolution & refresh rate from CGDisplayMode
            guard let mode = CGDisplayCopyDisplayMode(displayID) else { continue }
            
            // Points differ from pixels on HiDPI modes; the cable carries pixels.
            let width = mode.pixelWidth
            let height = mode.pixelHeight
            var refreshRate = mode.refreshRate
            
            // Fallback refresh rate from NSScreen if mode.refreshRate returns 0
            if refreshRate == 0 {
                refreshRate = getScreenRefreshRateFallback(displayID: displayID)
            }
            
            // Query HDR status from NSScreen
            let isHDR = getHDRSupport(displayID: displayID)
            let colorDepth = getScreenColorDepth(displayID: displayID)
            let displayName = getDisplayName(displayID: displayID)
            
            // Calculate raw video bandwidth in Gbps
            let bitsPerPixel = Double(colorDepth * 3)
            let rawBps = Double(width * height) * refreshRate * bitsPerPixel * 1.25 // 1.25 overhead factor
            let estimatedGbps = rawBps / 1_000_000_000.0
            
            let grade = HDMICableGrade.required(forEstimatedBandwidthGbps: estimatedGbps)
            let link = DisplayLinkMatcher.observation(
                for: (Int(CGDisplayModelNumber(displayID)), Int(CGDisplaySerialNumber(displayID)), displayName),
                in: transports,
                externalDisplayCount: externalCount
            ).map(DisplayLinkClassifier.assess)
            
            var device = HDMIDisplayDevice(
                displayID: displayID,
                displayName: displayName,
                widthPixels: width,
                heightPixels: height,
                refreshRateHz: refreshRate,
                isHDRSupported: isHDR,
                colorDepthBits: colorDepth,
                connectionTransport: link?.summary(italian: true) ?? "Trasporto non esposto da macOS",
                estimatedBandwidthGbps: estimatedGbps,
                cableGrade: grade
            )
            
            device.displayLink = link
            if let edid = edidReader?.readEDID(for: displayID) {
                device.apply(edid: edid)
            }
            detected.append(device)
        }
        
        self.externalDisplays = detected
        if let selected = selectedDisplay,
           externalDisplays.contains(where: { $0.displayID == selected.displayID }) {
            self.selectedDisplay = externalDisplays.first(where: { $0.displayID == selected.displayID })
        } else {
            self.selectedDisplay = externalDisplays.first
        }
    }
    
    // MARK: - Display Properties Helpers
    
    private func getDisplayName(displayID: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenNumber == displayID {
                return screen.localizedName
            }
        }
        return "Monitor esterno"
    }
    
    private func getScreenRefreshRateFallback(displayID: CGDirectDisplayID) -> Double {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenNumber == displayID {
                if #available(macOS 12.0, *) {
                    return Double(screen.maximumFramesPerSecond)
                }
            }
        }
        return 60.0
    }
    
    private func getHDRSupport(displayID: CGDirectDisplayID) -> Bool {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenNumber == displayID {
                return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0
            }
        }
        return false
    }
    
    private func getScreenColorDepth(displayID: CGDirectDisplayID) -> Int {
        for screen in NSScreen.screens {
            if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenNumber == displayID {
                let bps = screen.depth.bitsPerSample
                return bps > 0 ? bps : 8
            }
        }
        return 8
    }
    
    // MARK: - Reconfiguration Callback
    
    private static let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { _, _, context in
        guard let context else { return }
        let service = Unmanaged<HDMIDisplayDiscoveryService>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in service.scheduleRefresh() }
    }

    private func registerDisplayReconfigurationCallback() {
        CGDisplayRegisterReconfigurationCallback(Self.displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.refreshDisplays()
        }
    }
}
