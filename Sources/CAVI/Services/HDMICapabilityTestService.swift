import Foundation
import CoreGraphics
import CAVICore

@Observable
@MainActor
public final class HDMICapabilityTestService {
    public private(set) var isRunning: Bool = false
    public private(set) var testResults: [HDMICapabilityTestEntry] = []
    public private(set) var maximumStableMode: HDMICapabilityTestEntry?
    private var currentTestIndex: Int = 0

    public init() {}
    
    public func runProgressiveTest(displayID: CGDirectDisplayID) async {
        isRunning = true
        testResults = []
        let allModes = CGDisplayCopyAllDisplayModes(displayID, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
        let originalMode = CGDisplayCopyDisplayMode(displayID)
        
        let sorted = allModes.sorted { m1, m2 in
            let bw1 = Double(m1.width * m1.height) * m1.refreshRate
            let bw2 = Double(m2.width * m2.height) * m2.refreshRate
            return bw1 < bw2
        }
        
        for (index, mode) in sorted.enumerated() {
            guard isRunning else { break }
            currentTestIndex = index
            
            var config: CGDisplayConfigRef?
            CGBeginDisplayConfiguration(&config)
            CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
            let result = CGCompleteDisplayConfiguration(config, .forSession)
            
            if result == .success {
                try? await Task.sleep(for: .seconds(5))
                
                let stillActive = CGDisplayIsActive(displayID) != 0
                let entry = HDMICapabilityTestEntry(
                    id: UUID(),
                    modeDescription: "\(mode.width)x\(mode.height)@\(Int(mode.refreshRate))Hz",
                    width: mode.width, height: mode.height,
                    refreshRate: mode.refreshRate, bitDepth: 8,
                    chroma: .rgb444, isHDR: false,
                    bandwidthGbps: HDMIBandwidthCalculator.calculate(width: mode.width, height: mode.height, refreshRate: mode.refreshRate, bitDepth: 8, chroma: .rgb444, isDSC: false).totalBandwidthGbps,
                    status: stillActive ? .pass : .fail,
                    durationSeconds: 5, disconnects: stillActive ? 0 : 1, notes: nil
                )
                testResults.append(entry)
                if stillActive { maximumStableMode = entry }
            } else {
                testResults.append(HDMICapabilityTestEntry(id: UUID(), modeDescription: "\(mode.width)x\(mode.height)@\(Int(mode.refreshRate))Hz", width: mode.width, height: mode.height, refreshRate: mode.refreshRate, bitDepth: 8, chroma: .rgb444, isHDR: false, bandwidthGbps: 0, status: .fail, durationSeconds: nil, disconnects: 0, notes: "Mode switch rejected"))
            }
        }
        
        if let originalMode {
            var config: CGDisplayConfigRef?
            CGBeginDisplayConfiguration(&config)
            CGConfigureDisplayWithDisplayMode(config, displayID, originalMode, nil)
            CGCompleteDisplayConfiguration(config, .forSession)
        }
        isRunning = false
    }

    public func stopTest() { isRunning = false }
    public func isRunning(for displayID: CGDirectDisplayID) -> Bool { isRunning }
    public func startTest(for displayID: CGDirectDisplayID) { Task { await runProgressiveTest(displayID: displayID) } }
    public func stopTest(for displayID: CGDirectDisplayID) { stopTest() }
    public func results(for displayID: CGDirectDisplayID) -> [HDMICapabilityTestEntry] { return testResults }
    public func highestVerifiedMode(for displayID: CGDirectDisplayID) -> HDMICapabilityTestEntry? { return maximumStableMode }
    public func compatibilityMatrix(for displayID: CGDirectDisplayID) -> [HDMICompatibilityRow] { return [] }
    public func stabilityScore(for displayID: CGDirectDisplayID) -> Double { return 100.0 }
}
