import Foundation
import CoreGraphics
import CAVICore

@Observable
@MainActor
public final class HDMIStressTestService {
    public private(set) var isRunning: Bool = false
    public private(set) var events: [HDMIStressEvent] = []
    public private(set) var currentResult: HDMIStressTestResult?
    
    private var monitoringDisplayID: CGDirectDisplayID?
    private var elapsedSeconds: Int = 0
    private var timer: Timer?
    private var initialMode: CGDisplayMode?
    private var initialRefresh: Double = 0

    public init() {}
    
    public func startStressTest(displayID: CGDirectDisplayID, durationSeconds: Int) {
        guard !isRunning else { return }
        isRunning = true
        monitoringDisplayID = displayID
        elapsedSeconds = 0
        events = []
        
        initialMode = CGDisplayCopyDisplayMode(displayID)
        initialRefresh = initialMode?.refreshRate ?? 0
        let initialWidth = initialMode?.width ?? 0
        let initialHeight = initialMode?.height ?? 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.elapsedSeconds += 1
                
                let isActive = CGDisplayIsActive(displayID) != 0
                if !isActive {
                    self.recordEvent(.signalLoss, "Display signal lost at \(self.elapsedSeconds)s")
                }
                
                if let currentMode = CGDisplayCopyDisplayMode(displayID) {
                    if currentMode.width != initialWidth || currentMode.height != initialHeight {
                        self.recordEvent(.modeChange, "Resolution changed to \(currentMode.width)x\(currentMode.height)")
                    }
                    if currentMode.refreshRate != self.initialRefresh {
                        self.recordEvent(.renegotiation, "Refresh changed to \(currentMode.refreshRate) Hz")
                    }
                }
                
                if self.elapsedSeconds >= durationSeconds {
                    self.completeStressTest(durationSeconds: durationSeconds)
                }
            }
        }
    }

    private func recordEvent(_ type: HDMIStressEventType, _ description: String) {
        events.append(HDMIStressEvent(id: UUID(), timestamp: Date(), eventType: type, description: description))
    }

    private func completeStressTest(durationSeconds: Int) {
        timer?.invalidate()
        timer = nil
        isRunning = false
        
        let disconnects = events.filter { $0.eventType == .disconnect || $0.eventType == .signalLoss }.count
        let renegotiations = events.filter { $0.eventType == .renegotiation }.count
        let modeChanges = events.filter { $0.eventType == .modeChange }.count
        let stabilityScore = max(0, 100 - disconnects * 30 - renegotiations * 15 - modeChanges * 10)
        
        currentResult = HDMIStressTestResult(
            id: UUID(),
            mode: initialMode.map { "\($0.width)x\($0.height)@\(Int($0.refreshRate))Hz" } ?? "Unknown",
            durationSeconds: durationSeconds,
            disconnects: disconnects,
            renegotiations: renegotiations,
            modeChanges: modeChanges,
            hdcpFailures: 0,
            stabilityScore: stabilityScore,
            events: events
        )
    }

    public func stopStressTest() {
        completeStressTest(durationSeconds: elapsedSeconds)
    }
    
    public func isRunning(for displayID: CGDirectDisplayID) -> Bool { isRunning }
    public func start(for displayID: CGDirectDisplayID, durationMinutes: Int) {
        startStressTest(displayID: displayID, durationSeconds: durationMinutes * 60)
    }
    public func events(for displayID: CGDirectDisplayID) -> [HDMIStressEvent] { events }
    public func result(for displayID: CGDirectDisplayID) -> HDMIStressTestResult? { currentResult }
    
    // Add missing stop() function to match old protocol just in case
    public func stop(for displayID: CGDirectDisplayID) {
        stopStressTest()
    }
}
