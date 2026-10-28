import XCTest
@testable import CAVICore

final class HardwareEventAndHealthTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(_ id: String, speed: UInt64? = 5_000_000_000, protocolName: String? = "USB", mounted: Bool = false) -> HardwareConnectionState {
        HardwareConnectionState(id: id, displayName: "Device \(id)", linkSpeedBps: speed, protocolName: protocolName, isMounted: mounted)
    }

    private func event(_ kind: HardwareEventKind, _ id: String = "bsd:disk4", at offset: TimeInterval) -> HardwareEvent {
        HardwareEvent(timestamp: start.addingTimeInterval(offset), kind: kind, connectionID: id, displayName: "SSD")
    }

    // MARK: Event detection

    func testDuplicateIdentifiersDoNotTrap() {
        // Two identical peripherals without a location ID share an identifier.
        let twins = [state("peripheral:1:2:Mouse"), state("peripheral:1:2:Mouse")]
        let connected = HardwareEventDetector.changes(from: [], to: twins, timestamp: start)
        XCTAssertEqual(connected.map(\.kind), [.connected])

        let unchanged = HardwareEventDetector.changes(from: twins, to: twins, timestamp: start)
        XCTAssertEqual(unchanged, [])

        let removed = HardwareEventDetector.changes(from: twins, to: [], timestamp: start)
        XCTAssertEqual(removed.map(\.kind), [.disconnected])
    }

    func testDetectsEveryChangeInStableOrder() {
        let previous = [state("b", mounted: false), state("c")]
        let current = [state("a"), state("b", speed: 480_000_000, protocolName: "USB 2", mounted: true)]
        let events = HardwareEventDetector.changes(from: previous, to: current, timestamp: start)

        XCTAssertEqual(events.map(\.kind), [.connected, .disconnected, .linkRenegotiated, .protocolChanged, .mounted])
        XCTAssertEqual(events.map(\.connectionID), ["a", "c", "b", "b", "b"])
        XCTAssertEqual(events[2].previousLinkSpeedBps, 5_000_000_000)
        XCTAssertEqual(events[2].linkSpeedBps, 480_000_000)
        XCTAssertTrue(events.allSatisfy { $0.timestamp == start })
    }

    func testBoundedHistoryKeepsTheNewestPrefix() {
        let events = (0..<5).map { event(.connected, "\($0)", at: TimeInterval($0)) }
        XCTAssertEqual(HardwareEventHistory.bounded(events, limit: 2).map(\.connectionID), ["0", "1"])
        XCTAssertEqual(HardwareEventHistory.bounded(events, limit: 0), [])
        XCTAssertEqual(HardwareEventHistory.bounded(events, limit: 10).count, 5)
    }

    func testOlderLogsWithoutTheCancelledKindStillDecode() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","timestamp":0,"kind":"benchmarkFailed","connectionID":"x","displayName":"y"}]"#
        let decoded = try JSONDecoder().decode([HardwareEvent].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.kind, .benchmarkFailed)
    }

    // MARK: Stability score

    func testNoEventsMeansNoScore() {
        XCTAssertNil(EventStabilityScorer.score(for: []))
        XCTAssertEqual(EventStabilityScorer.penaltyBreakdown(for: []), [])
    }

    func testSafeEjectIsNotPenalisedButAbruptRemovalIs() {
        let safe = [event(.unmounted, at: 0), event(.disconnected, at: 1)]
        XCTAssertEqual(EventStabilityScorer.score(for: safe), 100)

        let abrupt = [event(.mounted, at: 0), event(.disconnected, at: 1)]
        XCTAssertEqual(EventStabilityScorer.score(for: abrupt), 80)

        // Order is chronological, not array order: the unmount came after the disconnect here.
        let outOfOrder = [event(.unmounted, at: 2), event(.disconnected, at: 1)]
        XCTAssertEqual(EventStabilityScorer.score(for: outOfOrder), 80)
    }

    func testUserCancelledBenchmarkCarriesNoPenalty() {
        let cancelled = [event(.benchmarkStarted, at: 0), event(.benchmarkCancelled, at: 1)]
        XCTAssertEqual(EventStabilityScorer.score(for: cancelled), 100)
        XCTAssertEqual(EventStabilityScorer.penaltyBreakdown(for: cancelled), [])

        let failed = [event(.benchmarkStarted, at: 0), event(.benchmarkFailed, at: 1)]
        XCTAssertEqual(EventStabilityScorer.score(for: failed), 92)
    }

    func testPenaltiesAccumulateAndFloorAtZero() {
        let events = [
            event(.linkRenegotiated, at: 0),
            event(.linkRenegotiated, at: 1),
            event(.protocolChanged, at: 2)
        ]
        XCTAssertEqual(EventStabilityScorer.score(for: events), 75)
        XCTAssertEqual(EventStabilityScorer.penaltyBreakdown(for: events), [
            StabilityPenaltyItem(kind: .linkRenegotiated, count: 2, totalDeduction: 20),
            StabilityPenaltyItem(kind: .protocolChanged, count: 1, totalDeduction: 5)
        ])

        let many = (0..<10).map { event(.disconnected, at: TimeInterval($0)) }
        XCTAssertEqual(EventStabilityScorer.score(for: many), 0)
    }

    // MARK: Drive health

    func testSMARTFailureAloneIsCritical() {
        let assessment = DriveHealthScorer.assess(DriveHealthInput(smartStatus: .failing))
        XCTAssertEqual(assessment.score, 50)
        XCTAssertEqual(assessment.level, .critical)
        XCTAssertEqual(assessment.warnings, [.smartFailure])
    }

    func testMissingDataIsNeutral() {
        let assessment = DriveHealthScorer.assess(DriveHealthInput())
        XCTAssertEqual(assessment.score, 100)
        XCTAssertEqual(assessment.level, .excellent)
        XCTAssertEqual(assessment.warnings, [])
    }

    func testThresholdsAndHugeErrorCounts() {
        XCTAssertEqual(DriveHealthScorer.assess(DriveHealthInput(smartStatus: .verified, temperatureCelsius: 69.9)).warnings, [])
        XCTAssertEqual(DriveHealthScorer.assess(DriveHealthInput(smartStatus: .verified, temperatureCelsius: 70)).warnings, [.highTemperature])
        XCTAssertEqual(DriveHealthScorer.assess(DriveHealthInput(remainingLifePercent: 11)).warnings, [])
        XCTAssertEqual(DriveHealthScorer.assess(DriveHealthInput(remainingLifePercent: 10)).score, 75)
        XCTAssertEqual(DriveHealthScorer.assess(DriveHealthInput(mediaErrorCount: 3)).score, 94)

        let huge = DriveHealthScorer.assess(DriveHealthInput(mediaErrorCount: Int.max))
        XCTAssertEqual(huge.score, 80, "The media-error penalty is capped and must not overflow")
        XCTAssertEqual(huge.level, .good)
    }
}
