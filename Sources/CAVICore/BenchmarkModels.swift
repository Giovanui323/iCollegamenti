import Foundation

public enum BenchmarkSize {
    public static let mebibyte: UInt64 = 1_024 * 1_024
    public static let gibibyte: UInt64 = 1_024 * mebibyte
}

public enum BenchmarkPreset: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case quick256MiB
    case standard1GiB
    case extended5GiB
    case extended10GiB
    case fiftyGiB
    case hundredGiB

    public var id: String { rawValue }

    public var sizeBytes: UInt64 {
        switch self {
        case .quick256MiB: 256 * BenchmarkSize.mebibyte
        case .standard1GiB: BenchmarkSize.gibibyte
        case .extended5GiB: 5 * BenchmarkSize.gibibyte
        case .extended10GiB: 10 * BenchmarkSize.gibibyte
        case .fiftyGiB: 50 * BenchmarkSize.gibibyte
        case .hundredGiB: 100 * BenchmarkSize.gibibyte
        }
    }

    public var requiresExplicitConfirmation: Bool {
        self == .fiftyGiB || self == .hundredGiB
    }
}

public enum BenchmarkWorkload: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case sequential
    case sustainedWrite
    case random4KRead
    case random4KWrite
    case mixedReadWrite
    case latency
    case integrity
    case stress

    public var id: String { rawValue }

    public var isReadOnly: Bool { self == .random4KRead }

    public var usesConfigurableRandomBlockSize: Bool {
        switch self {
        case .random4KRead, .random4KWrite, .mixedReadWrite:
            true
        case .sequential, .sustainedWrite, .latency, .integrity, .stress:
            false
        }
    }

    public var blockSizeBytes: Int {
        switch self {
        case .random4KRead, .random4KWrite, .mixedReadWrite, .latency, .integrity:
            4 * 1_024
        case .sequential, .sustainedWrite, .stress:
            1 * 1_024 * 1_024
        }
    }
}

public enum RandomBenchmarkBlockSize: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case fourKiB
    case sixteenKiB
    case sixtyFourKiB

    public var id: String { rawValue }

    public var bytes: Int {
        switch self {
        case .fourKiB: 4 * 1_024
        case .sixteenKiB: 16 * 1_024
        case .sixtyFourKiB: 64 * 1_024
        }
    }
}

public struct AdvancedBenchmarkConfiguration: Codable, Hashable, Sendable {
    public let preset: BenchmarkPreset
    public let workload: BenchmarkWorkload
    public let randomBlockSize: RandomBenchmarkBlockSize
    public let stressDurationSeconds: TimeInterval?
    public let seed: UInt64

    public init(
        preset: BenchmarkPreset,
        workload: BenchmarkWorkload,
        randomBlockSize: RandomBenchmarkBlockSize = .fourKiB,
        stressDurationSeconds: TimeInterval? = nil,
        seed: UInt64 = 0xCA71_2026
    ) {
        self.preset = preset
        self.workload = workload
        self.randomBlockSize = randomBlockSize
        self.stressDurationSeconds = stressDurationSeconds
        self.seed = seed
    }

    public var effectiveBlockSizeBytes: Int {
        workload.usesConfigurableRandomBlockSize ? randomBlockSize.bytes : workload.blockSizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case preset
        case workload
        case randomBlockSize
        case stressDurationSeconds
        case seed
    }

    /// Advanced histories created before block-size selection retain the
    /// original 4 KiB behaviour when decoded.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decode(BenchmarkPreset.self, forKey: .preset)
        workload = try container.decode(BenchmarkWorkload.self, forKey: .workload)
        randomBlockSize = try container.decodeIfPresent(RandomBenchmarkBlockSize.self, forKey: .randomBlockSize) ?? .fourKiB
        stressDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .stressDurationSeconds)
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed) ?? 0xCA71_2026
    }
}

public struct BenchmarkSample: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let transferredBytes: UInt64
    public let readMBps: Double?
    public let writeMBps: Double?
    public let latencyMilliseconds: Double?
    /// Observed only when the storage interface exposes temperature during this run.
    public let temperatureCelsius: Double?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        transferredBytes: UInt64,
        readMBps: Double? = nil,
        writeMBps: Double? = nil,
        latencyMilliseconds: Double? = nil,
        temperatureCelsius: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.transferredBytes = transferredBytes
        self.readMBps = readMBps
        self.writeMBps = writeMBps
        self.latencyMilliseconds = latencyMilliseconds
        self.temperatureCelsius = temperatureCelsius
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case transferredBytes
        case readMBps
        case writeMBps
        case latencyMilliseconds
        case temperatureCelsius
    }

    /// Old histories did not have a stable sample identifier. Keep those reports readable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        transferredBytes = try container.decode(UInt64.self, forKey: .transferredBytes)
        readMBps = try container.decodeIfPresent(Double.self, forKey: .readMBps)
        writeMBps = try container.decodeIfPresent(Double.self, forKey: .writeMBps)
        latencyMilliseconds = try container.decodeIfPresent(Double.self, forKey: .latencyMilliseconds)
        temperatureCelsius = try container.decodeIfPresent(Double.self, forKey: .temperatureCelsius)
    }
}

public struct AdvancedBenchmarkResult: Codable, Hashable, Sendable {
    public let configuration: AdvancedBenchmarkConfiguration
    public let samples: [BenchmarkSample]
    public let randomReadIOPS: Double?
    public let randomWriteIOPS: Double?
    public let latencyMinimumMilliseconds: Double?
    public let latencyAverageMilliseconds: Double?
    public let latencyMaximumMilliseconds: Double?
    public let latencyP95Milliseconds: Double?
    public let latencyP99Milliseconds: Double?
    public let integrityPassed: Bool?
    public let bytesVerified: UInt64?
    public let errorCount: Int

    public init(
        configuration: AdvancedBenchmarkConfiguration,
        samples: [BenchmarkSample],
        randomReadIOPS: Double? = nil,
        randomWriteIOPS: Double? = nil,
        latencyMinimumMilliseconds: Double? = nil,
        latencyAverageMilliseconds: Double? = nil,
        latencyMaximumMilliseconds: Double? = nil,
        latencyP95Milliseconds: Double? = nil,
        latencyP99Milliseconds: Double? = nil,
        integrityPassed: Bool? = nil,
        bytesVerified: UInt64? = nil,
        errorCount: Int = 0
    ) {
        self.configuration = configuration
        self.samples = samples
        self.randomReadIOPS = randomReadIOPS
        self.randomWriteIOPS = randomWriteIOPS
        self.latencyMinimumMilliseconds = latencyMinimumMilliseconds
        self.latencyAverageMilliseconds = latencyAverageMilliseconds
        self.latencyMaximumMilliseconds = latencyMaximumMilliseconds
        self.latencyP95Milliseconds = latencyP95Milliseconds
        self.latencyP99Milliseconds = latencyP99Milliseconds
        self.integrityPassed = integrityPassed
        self.bytesVerified = bytesVerified
        self.errorCount = errorCount
    }

    /// Attaches only measurements taken close to an existing benchmark sample.
    /// Temperatures without a same-session timestamp remain unavailable.
    public func applyingTemperatureObservations(
        _ observations: [BenchmarkTemperatureObservation],
        maximumAge: TimeInterval = 5
    ) -> AdvancedBenchmarkResult {
        let enrichedSamples = samples.map { sample -> BenchmarkSample in
            let closest = observations.min { lhs, rhs in
                abs(lhs.timestamp.timeIntervalSince(sample.timestamp)) < abs(rhs.timestamp.timeIntervalSince(sample.timestamp))
            }
            let temperature = closest.flatMap { observation -> Double? in
                let age = abs(observation.timestamp.timeIntervalSince(sample.timestamp))
                guard age <= maximumAge, observation.celsius.isFinite else { return nil }
                return observation.celsius
            }
            return BenchmarkSample(
                id: sample.id,
                timestamp: sample.timestamp,
                transferredBytes: sample.transferredBytes,
                readMBps: sample.readMBps,
                writeMBps: sample.writeMBps,
                latencyMilliseconds: sample.latencyMilliseconds,
                temperatureCelsius: temperature
            )
        }
        return AdvancedBenchmarkResult(
            configuration: configuration,
            samples: enrichedSamples,
            randomReadIOPS: randomReadIOPS,
            randomWriteIOPS: randomWriteIOPS,
            latencyMinimumMilliseconds: latencyMinimumMilliseconds,
            latencyAverageMilliseconds: latencyAverageMilliseconds,
            latencyMaximumMilliseconds: latencyMaximumMilliseconds,
            latencyP95Milliseconds: latencyP95Milliseconds,
            latencyP99Milliseconds: latencyP99Milliseconds,
            integrityPassed: integrityPassed,
            bytesVerified: bytesVerified,
            errorCount: errorCount
        )
    }

    public var thermalCorrelation: ThermalCorrelationResult {
        ThermalPerformanceCorrelation.assess(samples: samples)
    }
}
