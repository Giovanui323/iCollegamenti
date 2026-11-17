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
    /// Display the last result belongs to, so another monitor never shows it.
    private var resultDisplayID: CGDirectDisplayID?
    private var elapsedSeconds: Int = 0
    private var startedAt = Date()
    private var timer: Timer?
    private var initialMode: CGDisplayMode?
    private var initialRefresh: Double = 0
    /// Last observed state, used to record only transitions.
    private var lastActive = true
    private var lastWidth = 0
    private var lastHeight = 0
    private var lastRefresh: Double = 0

    public init() {}
    
    public func startStressTest(displayID: CGDirectDisplayID, durationSeconds: Int) {
        guard !isRunning else { return }
        isRunning = true
        monitoringDisplayID = displayID
        elapsedSeconds = 0
        startedAt = Date()
        events = []
        
        initialMode = CGDisplayCopyDisplayMode(displayID)
        initialRefresh = initialMode?.refreshRate ?? 0
        lastActive = true
        lastWidth = initialMode?.pixelWidth ?? 0
        lastHeight = initialMode?.pixelHeight ?? 0
        lastRefresh = initialRefresh

        // `.common` keeps the timer firing while a menu is open or a view scrolls; the elapsed time
        // comes from the clock, because counting ticks made the test run longer than requested.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isRunning else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(self.startedAt))
                
                // Record a change once, when the state changes, not on every second it lasts.
                let isActive = CGDisplayIsActive(displayID) != 0
                if isActive != self.lastActive {
                    if !isActive {
                        self.recordEvent(.signalLoss, "Display signal lost at \(self.elapsedSeconds)s")
                    } else {
                        // The loss was already counted; the restore is not a second disconnect.
                        self.recordEvent(.signalRestore, "Display signal restored at \(self.elapsedSeconds)s")
                    }
                    self.lastActive = isActive
                }

                if let currentMode = CGDisplayCopyDisplayMode(displayID) {
                    let resolutionChanged = currentMode.pixelWidth != self.lastWidth || currentMode.pixelHeight != self.lastHeight
                    if resolutionChanged {
                        self.recordEvent(.modeChange, "Resolution changed to \(currentMode.pixelWidth)x\(currentMode.pixelHeight)")
                    }
                    if currentMode.refreshRate != self.lastRefresh {
                        self.recordEvent(.renegotiation, "Refresh changed to \(currentMode.refreshRate) Hz")
                    }
                    self.lastWidth = currentMode.pixelWidth
                    self.lastHeight = currentMode.pixelHeight
                    self.lastRefresh = currentMode.refreshRate
                }
                
                if self.elapsedSeconds >= durationSeconds {
                    self.completeStressTest(durationSeconds: durationSeconds)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
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
            mode: initialMode.map { "\($0.pixelWidth)x\($0.pixelHeight)@\(Int($0.refreshRate.rounded()))Hz" } ?? "Unknown",
            durationSeconds: durationSeconds,
            disconnects: disconnects,
            renegotiations: renegotiations,
            modeChanges: modeChanges,
            hdcpFailures: 0, // Not measurable from software and not shown in the UI; do not read it as a result.
            stabilityScore: stabilityScore,
            events: events
        )
        resultDisplayID = monitoringDisplayID
    }

    public func stopStressTest() {
        guard isRunning else { return }
        completeStressTest(durationSeconds: Int(Date().timeIntervalSince(startedAt)))
    }

    /// Only the monitored display is running; other monitors must not show its progress.
    public func isRunning(for displayID: CGDirectDisplayID) -> Bool { isRunning && monitoringDisplayID == displayID }
    public func start(for displayID: CGDirectDisplayID, durationMinutes: Int) {
        startStressTest(displayID: displayID, durationSeconds: durationMinutes * 60)
    }
    public func events(for displayID: CGDirectDisplayID) -> [HDMIStressEvent] { monitoringDisplayID == displayID ? events : [] }
    public func result(for displayID: CGDirectDisplayID) -> HDMIStressTestResult? { resultDisplayID == displayID ? currentResult : nil }
    
    // Add missing stop() function to match old protocol just in case
    public func stop(for displayID: CGDirectDisplayID) {
        stopStressTest()
    }
}
