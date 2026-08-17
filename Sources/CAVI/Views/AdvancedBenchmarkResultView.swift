import SwiftUI
import Charts
import CAVICore

struct AdvancedBenchmarkResultView: View {
    let result: AdvancedBenchmarkResult
    let languageManager: LanguageManager

    private var latestReadMBps: Double? {
        result.samples.reversed().compactMap(\.readMBps).first
    }

    private var latestWriteMBps: Double? {
        result.samples.reversed().compactMap(\.writeMBps).first
    }

    private var hasThroughputSamples: Bool {
        result.samples.contains { $0.readMBps != nil || $0.writeMBps != nil }
    }

    private var hasTemperatureSamples: Bool {
        result.samples.contains { $0.temperatureCelsius != nil }
    }

    var body: some View {
        GroupBox(languageManager.t("Advanced Benchmark Result", "Risultato benchmark avanzato")) {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent(languageManager.t("Workload", "Carico"), value: result.configuration.workload.title(using: languageManager))
                LabeledContent(languageManager.t("Data set", "Set di dati"), value: result.configuration.preset.formattedSize)
                if result.configuration.workload.usesConfigurableRandomBlockSize {
                    LabeledContent(
                        languageManager.t("Random block size", "Dimensione blocco casuale"),
                        value: ByteCountFormatter.string(fromByteCount: Int64(result.configuration.effectiveBlockSizeBytes), countStyle: .file)
                    )
                }

                if let read = latestReadMBps {
                    LabeledContent(languageManager.t("Read", "Lettura"), value: Self.speed(read))
                }
                if let write = latestWriteMBps {
                    LabeledContent(languageManager.t("Write", "Scrittura"), value: Self.speed(write))
                }
                if let readIOPS = result.randomReadIOPS {
                    LabeledContent(languageManager.t("Random read", "Lettura casuale"), value: Self.iops(readIOPS))
                }
                if let writeIOPS = result.randomWriteIOPS {
                    LabeledContent(languageManager.t("Random write", "Scrittura casuale"), value: Self.iops(writeIOPS))
                }
                if let minimum = result.latencyMinimumMilliseconds {
                    LabeledContent(languageManager.t("Latency minimum", "Latenza minima"), value: Self.latency(minimum))
                }
                if let average = result.latencyAverageMilliseconds {
                    LabeledContent(languageManager.t("Latency average", "Latenza media"), value: Self.latency(average))
                }
                if let maximum = result.latencyMaximumMilliseconds {
                    LabeledContent(languageManager.t("Latency maximum", "Latenza massima"), value: Self.latency(maximum))
                }
                if let p95 = result.latencyP95Milliseconds {
                    LabeledContent(languageManager.t("Latency p95", "Latenza p95"), value: Self.latency(p95))
                }
                if let p99 = result.latencyP99Milliseconds {
                    LabeledContent(languageManager.t("Latency p99", "Latenza p99"), value: Self.latency(p99))
                }
                if let integrityPassed = result.integrityPassed {
                    SemanticStatus(
                        integrityPassed
                            ? languageManager.t("Integrity verification passed", "Verifica d’integrità superata")
                            : languageManager.t("Integrity verification failed", "Verifica d’integrità non superata"),
                        systemImage: integrityPassed ? "checkmark.shield.fill" : "xmark.shield.fill",
                        tone: integrityPassed ? .success : .error
                    )
                    if let bytesVerified = result.bytesVerified {
                        LabeledContent(languageManager.t("Verified", "Verificati"), value: ByteCountFormatter.string(fromByteCount: Int64(bytesVerified), countStyle: .file))
                    }
                }

                if result.configuration.workload == .sustainedWrite || result.configuration.workload == .stress {
                    thermalCorrelationSummary
                }

                if hasThroughputSamples {
                    Divider()
                    Chart(result.samples) { sample in
                        if let read = sample.readMBps {
                            LineMark(
                                x: .value(languageManager.t("Time", "Tempo"), sample.timestamp),
                                y: .value(languageManager.t("MB/s", "MB/s"), read)
                            )
                            .foregroundStyle(.blue)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value(languageManager.t("Time", "Tempo"), sample.timestamp),
                                y: .value(languageManager.t("MB/s", "MB/s"), read)
                            )
                            .foregroundStyle(.blue)
                        }
                        if let write = sample.writeMBps {
                            LineMark(
                                x: .value(languageManager.t("Time", "Tempo"), sample.timestamp),
                                y: .value(languageManager.t("MB/s", "MB/s"), write)
                            )
                            .foregroundStyle(.orange)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value(languageManager.t("Time", "Tempo"), sample.timestamp),
                                y: .value(languageManager.t("MB/s", "MB/s"), write)
                            )
                            .foregroundStyle(.orange)
                        }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 180)
                    HStack(spacing: 14) {
                        Label(languageManager.t("Read", "Lettura"), systemImage: "circle.fill")
                            .foregroundStyle(.blue)
                        Label(languageManager.t("Write", "Scrittura"), systemImage: "circle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                }

                if hasTemperatureSamples {
                    Divider()
                    Text(languageManager.t(
                        "Temperature sampled during this benchmark",
                        "Temperatura campionata durante questo benchmark"
                    ))
                    .font(.caption.weight(.semibold))
                    Chart(result.samples) { sample in
                        if let temperature = sample.temperatureCelsius {
                            LineMark(
                                x: .value(languageManager.t("Time", "Tempo"), sample.timestamp),
                                y: .value(languageManager.t("Temperature (°C)", "Temperatura (°C)"), temperature)
                            )
                            .foregroundStyle(.red)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value(languageManager.t("Time", "Tempo"), sample.timestamp),
                                y: .value(languageManager.t("Temperature (°C)", "Temperatura (°C)"), temperature)
                            )
                            .foregroundStyle(.red)
                        }
                    }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 130)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var thermalCorrelationSummary: some View {
        let correlation = result.thermalCorrelation
        switch correlation.state {
        case .unavailable:
            SemanticStatus(
                languageManager.t("Thermal correlation unavailable", "Correlazione termica non disponibile"),
                systemImage: "thermometer.medium.slash",
                tone: .neutral
            )
            Text(languageManager.t(
                "This storage interface did not provide enough temperature samples from this same benchmark session.",
                "Questa interfaccia di archiviazione non ha fornito abbastanza campioni di temperatura della stessa sessione di benchmark."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        case .notDetected:
            SemanticStatus(
                languageManager.t("No temperature-throughput pattern observed", "Nessuna correlazione temperatura-throughput osservata"),
                systemImage: "thermometer.medium",
                tone: .success
            )
        case .possibleThermalThrottling:
            let peak = correlation.peakTemperatureCelsius.map { String(format: "%.0f °C", $0) } ?? "—"
            let drop = correlation.throughputDropPercent.map { String(format: "%.0f%%", $0) } ?? "—"
            let englishMessage = "Possible thermal throttling: " + drop + " lower throughput at higher temperature (peak " + peak + ")."
            let italianMessage = "Possibile throttling termico: throughput " + drop + " più basso a temperatura elevata (picco " + peak + ")."
            SemanticStatus(
                languageManager.t(englishMessage, italianMessage),
                systemImage: "thermometer.high",
                tone: .warning
            )
        }
    }

    private static func speed(_ value: Double) -> String {
        String(format: "%.1f MB/s", value)
    }

    private static func iops(_ value: Double) -> String {
        String(format: "%.0f IOPS", value)
    }

    private static func latency(_ value: Double) -> String {
        String(format: "%.2f ms", value)
    }
}

private extension BenchmarkPreset {
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(sizeBytes), countStyle: .file)
    }
}

private extension BenchmarkWorkload {
    func title(using languageManager: LanguageManager) -> String {
        switch self {
        case .sequential:
            languageManager.t("Sequential read and write", "Lettura e scrittura sequenziale")
        case .sustainedWrite:
            languageManager.t("Sustained write", "Scrittura sostenuta")
        case .random4KRead:
            languageManager.t("Random 4K read", "Lettura casuale 4K")
        case .random4KWrite:
            languageManager.t("Random 4K write", "Scrittura casuale 4K")
        case .mixedReadWrite:
            languageManager.t("Mixed read and write", "Lettura e scrittura mista")
        case .latency:
            languageManager.t("Latency", "Latenza")
        case .integrity:
            languageManager.t("Data integrity", "Integrità dati")
        case .stress:
            languageManager.t("Stress test", "Stress test")
        }
    }
}
