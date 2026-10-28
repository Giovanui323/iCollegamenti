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
    /// Display the results belong to, so another monitor never shows them.
    private var testedDisplayID: CGDirectDisplayID?

    public init() {}

    /// Switches the display through its modes and checks that macOS keeps each one.
    /// This does not check the picture: software cannot see what the monitor shows. A mode counts as
    /// `pass` only when the system reports it active after the hold time, and the original mode is
    /// restored on every exit path, including cancellation and errors.
    public func runProgressiveTest(displayID: CGDirectDisplayID) async {
        isRunning = true
        testResults = []
        maximumStableMode = nil
        testedDisplayID = displayID
        defer { isRunning = false }

        let allModes = CGDisplayCopyAllDisplayModes(displayID, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode] ?? []
        let originalMode = CGDisplayCopyDisplayMode(displayID)
        defer {
            if let originalMode { _ = Self.apply(originalMode, to: displayID) }
        }

        // The cable carries the pixel size, not the point size, and HiDPI variants of one
        // pixel mode put the same signal on the link: test each signal once.
        var seenSignals = Set<String>()
        let sorted = allModes
            .filter { seenSignals.insert("\($0.pixelWidth)x\($0.pixelHeight)@\($0.refreshRate)").inserted }
            .sorted { m1, m2 in
                let bw1 = Double(m1.pixelWidth * m1.pixelHeight) * m1.refreshRate
                let bw2 = Double(m2.pixelWidth * m2.pixelHeight) * m2.refreshRate
                return bw1 < bw2
            }

        for (index, mode) in sorted.enumerated() {
            guard isRunning, !Task.isCancelled else { break }
            currentTestIndex = index
            let description = "\(mode.pixelWidth)x\(mode.pixelHeight)@\(Int(mode.refreshRate.rounded()))Hz"
            let bandwidth = HDMIBandwidthCalculator.calculate(width: mode.pixelWidth, height: mode.pixelHeight, refreshRate: mode.refreshRate, bitDepth: 8, chroma: .rgb444, isDSC: false).totalBandwidthGbps

            guard Self.apply(mode, to: displayID) else {
                testResults.append(HDMICapabilityTestEntry(id: UUID(), modeDescription: description, width: mode.pixelWidth, height: mode.pixelHeight, refreshRate: mode.refreshRate, bitDepth: 8, chroma: .rgb444, isHDR: false, bandwidthGbps: bandwidth, status: .fail, durationSeconds: nil, disconnects: 0, notes: "Mode switch rejected"))
                continue
            }

            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                break
            }

            let kept = Self.isActive(mode, on: displayID)
            let entry = HDMICapabilityTestEntry(
                id: UUID(),
                modeDescription: description,
                width: mode.pixelWidth, height: mode.pixelHeight,
                refreshRate: mode.refreshRate, bitDepth: 8,
                chroma: .rgb444, isHDR: false,
                bandwidthGbps: bandwidth,
                status: kept ? .pass : .fail,
                durationSeconds: 5,
                disconnects: kept ? 0 : 1,
                notes: kept
                    ? "macOS kept this mode for 5 s. The picture itself is not verified by software."
                    : "macOS did not keep this mode for 5 s."
            )
            testResults.append(entry)
            if kept { maximumStableMode = entry }
        }
    }

    public func stopTest() { isRunning = false }
    public func isRunning(for displayID: CGDirectDisplayID) -> Bool { isRunning }
    public func startTest(for displayID: CGDirectDisplayID) { Task { await runProgressiveTest(displayID: displayID) } }
    public func stopTest(for displayID: CGDirectDisplayID) { stopTest() }
    public func results(for displayID: CGDirectDisplayID) -> [HDMICapabilityTestEntry] { testedDisplayID == displayID ? testResults : [] }
    public func highestVerifiedMode(for displayID: CGDirectDisplayID) -> HDMICapabilityTestEntry? { testedDisplayID == displayID ? maximumStableMode : nil }
    /// Modes the EDID advertises, joined with what the progressive test observed on this display.
    public func compatibilityMatrix(for displayID: CGDirectDisplayID, edid: ParsedEDID?) -> [HDMIModeCompatibility] {
        HDMICompatibilityMatrixGenerator.matrix(edid: edid, testResults: results(for: displayID))
    }

    /// Share of the tested modes that macOS kept active. Zero when nothing has been tested yet.
    public func stabilityScore(for displayID: CGDirectDisplayID) -> Double {
        let results = results(for: displayID)
        guard !results.isEmpty else { return 0 }
        let kept = results.filter { $0.status == .pass }.count
        return Double(kept) / Double(results.count) * 100
    }

    private static func apply(_ mode: CGDisplayMode, to displayID: CGDirectDisplayID) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    private static func isActive(_ mode: CGDisplayMode, on displayID: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsActive(displayID) != 0,
              let current = CGDisplayCopyDisplayMode(displayID) else { return false }
        return current.pixelWidth == mode.pixelWidth && current.pixelHeight == mode.pixelHeight
            && abs(current.refreshRate - mode.refreshRate) < 0.5
    }
}
