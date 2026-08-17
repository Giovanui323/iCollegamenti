import Foundation

/// A temperature reading paired with a benchmark session timestamp. This is not
/// SMART history; it exists solely to compare a measured run with its own data.
public struct BenchmarkTemperatureObservation: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let celsius: Double

    public init(id: UUID = UUID(), timestamp: Date, celsius: Double) {
        self.id = id
        self.timestamp = timestamp
        self.celsius = celsius
    }
}

public enum ThermalCorrelationState: String, Codable, Hashable, Sendable {
    case unavailable
    case notDetected
    case possibleThermalThrottling
}

public struct ThermalCorrelationResult: Codable, Hashable, Sendable {
    public let state: ThermalCorrelationState
    public let peakTemperatureCelsius: Double?
    public let throughputDropPercent: Double?

    public init(
        state: ThermalCorrelationState,
        peakTemperatureCelsius: Double? = nil,
        throughputDropPercent: Double? = nil
    ) {
        self.state = state
        self.peakTemperatureCelsius = peakTemperatureCelsius
        self.throughputDropPercent = throughputDropPercent
    }
}

/// Conservative, same-session correlation. It never diagnoses throttling from
/// a speed drop alone and requires four paired temperature/throughput samples.
public enum ThermalPerformanceCorrelation {
    public static func assess(samples: [BenchmarkSample]) -> ThermalCorrelationResult {
        let paired = samples.compactMap { sample -> (temperature: Double, throughput: Double)? in
            guard let temperature = sample.temperatureCelsius else {
                return nil
            }
            let throughput = max(sample.readMBps ?? 0, sample.writeMBps ?? 0)
            guard temperature.isFinite, throughput.isFinite, throughput >= 0 else { return nil }
            return (temperature, throughput)
        }
        guard paired.count >= 4, let midpoint = AnalysisMetrics.median(paired.map(\.temperature)) else {
            return ThermalCorrelationResult(state: .unavailable)
        }

        let cooler = paired.filter { $0.temperature <= midpoint }.map(\.throughput)
        let hotter = paired.filter { $0.temperature > midpoint }.map(\.throughput)
        guard let coolAverage = AnalysisMetrics.average(cooler),
              let hotAverage = AnalysisMetrics.average(hotter),
              coolAverage > 0 else {
            return ThermalCorrelationResult(state: .unavailable)
        }

        let drop = max(0, (1 - hotAverage / coolAverage) * 100)
        let peak = paired.map(\.temperature).max()
        let state: ThermalCorrelationState = (peak ?? 0) >= 70 && drop >= 20
            ? .possibleThermalThrottling
            : .notDetected
        return ThermalCorrelationResult(
            state: state,
            peakTemperatureCelsius: peak,
            throughputDropPercent: drop
        )
    }
}
