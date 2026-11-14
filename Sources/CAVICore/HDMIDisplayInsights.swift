import Foundation

// MARK: - EDID-derived capabilities

public enum EDIDModeSource: String, Codable, Hashable, Sendable {
    case detailedTiming
    case ctaVideoMode
    case standardTiming
    case testedByMac
}

/// A video mode the display advertises in its EDID.
public struct HDMIAdvertisedMode: Codable, Hashable, Sendable, Identifiable {
    public let width: Int
    public let height: Int
    public let refreshRate: Double
    public let isNative: Bool
    public let source: EDIDModeSource

    public init(width: Int, height: Int, refreshRate: Double, isNative: Bool, source: EDIDModeSource) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        self.isNative = isNative
        self.source = source
    }

    public var id: String { "\(width)x\(height)@\(Int(refreshRate.rounded()))" }
}

public extension ParsedEDID {
    /// Every 128-byte block present must sum to 0 modulo 256 (VESA E-EDID).
    var isChecksumValid: Bool {
        let blockCount = min(extensionCount + 1, rawBytes.count / 128)
        guard blockCount > 0 else { return false }
        return (0..<blockCount).allSatisfy { block in
            rawBytes[(block * 128)..<((block + 1) * 128)].reduce(UInt8(0), &+) == 0
        }
    }

    var supportsHDR10: Bool { ctaExtension?.hdrCapabilities?.supportsSMPTE_ST_2084 == true }
    var supportsHLG: Bool { ctaExtension?.hdrCapabilities?.supportsHLG == true }

    /// Highest link rate the display claims, in Gb/s: TMDS (3 channels × 10 bits per clock)
    /// or HDMI 2.1 FRL, whichever is larger. Nil when the EDID states neither.
    var advertisedLinkCapacityGbps: Double? {
        let vendor = ctaExtension?.hdmiVendorBlock
        let tmds = vendor?.maxTMDSClockMHz.map { Double($0) * 30 / 1_000 }
        let frl = vendor?.maxFRLRateGbps.map(Double.init)
        return [tmds, frl].compactMap { $0 }.max()
    }

    /// Unique progressive modes from detailed timings, CTA video modes and standard timings,
    /// largest pixel rate first.
    var advertisedModes: [HDMIAdvertisedMode] {
        var modes: [HDMIAdvertisedMode] = []
        for (index, timing) in detailedTimings.enumerated() where !timing.isInterlaced && timing.refreshRate > 0 {
            modes.append(HDMIAdvertisedMode(width: timing.hActive, height: timing.vActive, refreshRate: timing.refreshRate, isNative: index == 0, source: .detailedTiming))
        }
        for mode in ctaExtension?.supportedVideoModes ?? [] where !mode.isInterlaced {
            modes.append(HDMIAdvertisedMode(width: mode.width, height: mode.height, refreshRate: mode.refreshRate, isNative: mode.isNative, source: .ctaVideoMode))
        }
        for timing in standardTimings where timing.height > 0 {
            modes.append(HDMIAdvertisedMode(width: timing.width, height: timing.height, refreshRate: Double(timing.refreshRate), isNative: false, source: .standardTiming))
        }
        return HDMIAdvertisedMode.uniqued(modes)
    }
}

extension HDMIAdvertisedMode {
    /// Keeps the first occurrence of each size/refresh, merging the native flag.
    static func uniqued(_ modes: [HDMIAdvertisedMode]) -> [HDMIAdvertisedMode] {
        var order: [String] = []
        var byID: [String: HDMIAdvertisedMode] = [:]
        for mode in modes {
            if let existing = byID[mode.id] {
                if mode.isNative && !existing.isNative {
                    byID[mode.id] = HDMIAdvertisedMode(width: existing.width, height: existing.height, refreshRate: existing.refreshRate, isNative: true, source: existing.source)
                }
            } else {
                order.append(mode.id)
                byID[mode.id] = mode
            }
        }
        return order.compactMap { byID[$0] }.sorted {
            Double($0.width * $0.height) * $0.refreshRate > Double($1.width * $1.height) * $1.refreshRate
        }
    }
}

// MARK: - Compatibility matrix

/// One row of the compatibility matrix: what the display advertises, whether it fits the
/// link the display claims, and what the progressive test observed on this Mac.
public struct HDMIModeCompatibility: Codable, Hashable, Sendable, Identifiable {
    public let mode: HDMIAdvertisedMode
    /// 8-bit RGB with TMDS overhead, the baseline signal macOS sends.
    public let requiredBandwidthGbps: Double
    /// Nil when the EDID does not state a link capacity.
    public let fitsAdvertisedLink: Bool?
    public let testStatus: HDMICapabilityTestStatus

    public var id: String { mode.id }
}

public extension HDMICompatibilityMatrixGenerator {
    static func matrix(edid: ParsedEDID?, testResults: [HDMICapabilityTestEntry]) -> [HDMIModeCompatibility] {
        // Modes the Mac tested but the EDID does not list are still worth showing.
        let tested = testResults.map {
            HDMIAdvertisedMode(width: $0.width, height: $0.height, refreshRate: $0.refreshRate, isNative: false, source: .testedByMac)
        }
        let modes = HDMIAdvertisedMode.uniqued((edid?.advertisedModes ?? []) + tested)
        let capacity = edid?.advertisedLinkCapacityGbps

        return modes.map { mode in
            let required = HDMIBandwidthCalculator.calculate(
                width: mode.width, height: mode.height, refreshRate: mode.refreshRate,
                bitDepth: 8, chroma: .rgb444, isDSC: false
            ).totalBandwidthGbps
            let matches = testResults.filter {
                $0.width == mode.width && $0.height == mode.height && abs($0.refreshRate - mode.refreshRate) < 0.6
            }
            let status: HDMICapabilityTestStatus
            if matches.contains(where: { $0.status == .pass }) {
                status = .pass
            } else if matches.contains(where: { $0.status == .fail }) {
                status = .fail
            } else {
                status = .untested
            }
            return HDMIModeCompatibility(
                mode: mode,
                requiredBandwidthGbps: required,
                fitsAdvertisedLink: capacity.map { required <= $0 },
                testStatus: status
            )
        }
    }
}

// MARK: - Diagnosis checklist

public enum HDMIChecklistItemKind: String, Codable, CaseIterable, Hashable, Sendable {
    case edidIntegrity
    case nativeResolution
    case linkBandwidth
    case chromaQuality
    case hdr
    case signalStability
}

public enum HDMIChecklistStatus: String, Codable, Hashable, Sendable {
    case passed
    case attention
    case failed
    case unavailable
}

/// A check computed only from the active signal, the EDID and an optional stress test.
/// Values are raw so the app can localise the description.
public struct HDMIChecklistItem: Codable, Hashable, Sendable, Identifiable {
    public let kind: HDMIChecklistItemKind
    public let status: HDMIChecklistStatus
    public let observed: String?
    public let expected: String?

    public var id: HDMIChecklistItemKind { kind }

    public init(kind: HDMIChecklistItemKind, status: HDMIChecklistStatus, observed: String? = nil, expected: String? = nil) {
        self.kind = kind
        self.status = status
        self.observed = observed
        self.expected = expected
    }
}

public enum HDMIDiagnosisChecklist {
    public static func items(
        signal: HDMISignalConfiguration?,
        edid: ParsedEDID?,
        stress: HDMIStressTestResult?
    ) -> [HDMIChecklistItem] {
        [
            edidIntegrity(edid),
            nativeResolution(signal: signal, edid: edid),
            linkBandwidth(signal: signal, edid: edid),
            chromaQuality(signal),
            hdr(signal: signal, edid: edid),
            stability(stress)
        ]
    }

    private static func edidIntegrity(_ edid: ParsedEDID?) -> HDMIChecklistItem {
        guard let edid else { return HDMIChecklistItem(kind: .edidIntegrity, status: .unavailable) }
        return HDMIChecklistItem(kind: .edidIntegrity, status: edid.isChecksumValid ? .passed : .failed, observed: edid.edidVersion)
    }

    private static func nativeResolution(signal: HDMISignalConfiguration?, edid: ParsedEDID?) -> HDMIChecklistItem {
        guard let signal, let native = edid?.nativeResolution else {
            return HDMIChecklistItem(kind: .nativeResolution, status: .unavailable)
        }
        let isNative = signal.width >= native.width && signal.height >= native.height
        return HDMIChecklistItem(
            kind: .nativeResolution,
            status: isNative ? .passed : .attention,
            observed: "\(signal.width)x\(signal.height)",
            expected: "\(native.width)x\(native.height)"
        )
    }

    private static func linkBandwidth(signal: HDMISignalConfiguration?, edid: ParsedEDID?) -> HDMIChecklistItem {
        guard let signal, let capacity = edid?.advertisedLinkCapacityGbps else {
            return HDMIChecklistItem(kind: .linkBandwidth, status: .unavailable)
        }
        let required = signal.bandwidthRequirement.effectiveBandwidthGbps
        let headroom = HDMIBandwidthCalculator.headroom(required: required, available: capacity)
        let status: HDMIChecklistStatus
        switch headroom.headroomLevel {
        case .comfortable, .adequate: status = .passed
        case .tight, .critical: status = .attention
        case .exceeded: status = .failed
        }
        return HDMIChecklistItem(
            kind: .linkBandwidth,
            status: status,
            observed: String(format: "%.1f Gb/s", required),
            expected: String(format: "%.1f Gb/s", capacity)
        )
    }

    private static func chromaQuality(_ signal: HDMISignalConfiguration?) -> HDMIChecklistItem {
        guard let signal else { return HDMIChecklistItem(kind: .chromaQuality, status: .unavailable) }
        let full = signal.chroma == .rgb444 || signal.chroma == .ycbcr444
        return HDMIChecklistItem(kind: .chromaQuality, status: full ? .passed : .attention, observed: signal.chroma.rawValue)
    }

    private static func hdr(signal: HDMISignalConfiguration?, edid: ParsedEDID?) -> HDMIChecklistItem {
        let displaySupportsHDR = edid?.ctaExtension?.hdrCapabilities?.supportsHDR == true
        guard let signal else { return HDMIChecklistItem(kind: .hdr, status: .unavailable) }
        if signal.isHDRActive { return HDMIChecklistItem(kind: .hdr, status: .passed, observed: "HDR") }
        // HDR off on an HDR display may be a choice; it is worth a look, not a failure.
        return HDMIChecklistItem(kind: .hdr, status: displaySupportsHDR ? .attention : .unavailable, observed: "SDR")
    }

    private static func stability(_ stress: HDMIStressTestResult?) -> HDMIChecklistItem {
        guard let stress, stress.durationSeconds > 0 else {
            return HDMIChecklistItem(kind: .signalStability, status: .unavailable)
        }
        let status: HDMIChecklistStatus = stress.disconnects > 0 ? .failed
            : (stress.renegotiations > 0 || stress.modeChanges > 0 ? .attention : .passed)
        return HDMIChecklistItem(kind: .signalStability, status: status, observed: "\(stress.disconnects)", expected: "\(stress.durationSeconds)")
    }
}

// MARK: - Connection score

public extension HDMIScoringEngine {
    /// Connection score from a completed stress test, plus bandwidth headroom when the EDID
    /// states a link capacity. Without a stress test nothing about the connection was measured.
    static func observedConnectionScore(
        signal: HDMISignalConfiguration?,
        edid: ParsedEDID?,
        stress: HDMIStressTestResult?
    ) -> HDMIConnectionScore? {
        guard let stress, stress.durationSeconds > 0 else { return nil }
        let disconnects = max(0, min(stress.disconnects, 100))
        let renegotiations = max(0, min(stress.renegotiations, 100))
        let stability = max(0, min(100, stress.stabilityScore))
        let handshake = max(0, 100 - disconnects * 15 - renegotiations * 5)

        var bandwidth: Int? = nil
        if let signal, let capacity = edid?.advertisedLinkCapacityGbps {
            let headroom = HDMIBandwidthCalculator.headroom(required: signal.bandwidthRequirement.effectiveBandwidthGbps, available: capacity)
            let percent = headroom.headroomPercent.isFinite ? headroom.headroomPercent : 0
            bandwidth = Int(min(100, max(0, percent * 2.5 + 50)))
        }
        let components = [stability, handshake] + (bandwidth.map { [$0] } ?? [])
        let overall = Int((Double(components.reduce(0, +)) / Double(components.count)).rounded())
        let level: HDMIScoreLevel = overall >= 90 ? .excellent : overall >= 75 ? .good : overall >= 50 ? .adequate : overall >= 25 ? .poor : .critical
        let isHDR = signal?.isHDRActive ?? false
        let audioFormats = edid?.ctaExtension?.audioFormats ?? []
        return HDMIConnectionScore(
            overall: overall,
            level: level,
            bandwidth: bandwidth ?? 0,
            signalConfig: isHDR ? 100 : 80,
            stability: stability,
            hdr: isHDR ? 100 : 0,
            audio: audioFormats.isEmpty ? 50 : min(100, audioFormats.count * 15 + 40),
            handshake: handshake,
            bandwidthObserved: bandwidth != nil
        )
    }
}

// MARK: - Link reference for the signal view

/// The link capacity the signal is compared against: what the display states in its EDID
/// when it does, otherwise the HDMI 2.1 ceiling, which is theoretical for this connection.
public struct HDMILinkReference: Codable, Hashable, Sendable {
    public let capacityGbps: Double
    public let isStatedByDisplay: Bool

    public init(edid: ParsedEDID?) {
        if let stated = edid?.advertisedLinkCapacityGbps, stated > 0 {
            capacityGbps = stated
            isStatedByDisplay = true
        } else {
            capacityGbps = HDMIStandard.hdmi21.maxBandwidthGbps
            isStatedByDisplay = false
        }
    }

    /// Share of the link left free by a signal, 0…1.
    public func freeShare(requiredGbps: Double) -> Double {
        guard capacityGbps > 0, requiredGbps.isFinite else { return 0 }
        return min(1, max(0, (capacityGbps - requiredGbps) / capacityGbps))
    }
}
