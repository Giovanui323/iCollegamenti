import Foundation

public enum BenchmarkSafetyDecision: Equatable, Sendable {
    case allowed
    case requiresConfirmation
    case insufficientSpace(requiredBytes: UInt64)
}

/// Pure safety checks for benchmarks that create only exclusive temporary
/// files. Large tests leave the user a substantial free-space reserve.
public enum BenchmarkSafetyPolicy {
    public static func requiredFreeBytes(
        for preset: BenchmarkPreset,
        volumeCapacityBytes: UInt64
    ) -> UInt64 {
        if preset.requiresExplicitConfirmation {
            let percentageReserve = volumeCapacityBytes / 100 * 15
            let reserve = max(20 * BenchmarkSize.gibibyte, percentageReserve)
            return preset.sizeBytes + reserve
        }
        return preset.sizeBytes * 2
    }

    public static func decision(
        preset: BenchmarkPreset,
        freeBytes: UInt64,
        volumeCapacityBytes: UInt64,
        userConfirmedExtendedTest: Bool
    ) -> BenchmarkSafetyDecision {
        let required = requiredFreeBytes(for: preset, volumeCapacityBytes: volumeCapacityBytes)
        guard freeBytes >= required else { return .insufficientSpace(requiredBytes: required) }
        guard !preset.requiresExplicitConfirmation || userConfirmedExtendedTest else {
            return .requiresConfirmation
        }
        return .allowed
    }
}
