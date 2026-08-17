import Foundation
import CAVICore

@Observable
@MainActor
final class BenchmarkService {
    var isRunning = false
    var progress = 0.0
    var currentPhase = ""
    var lastResult: BenchmarkResult?
    var lastAdvancedResult: AdvancedBenchmarkResult?
    var errorMessage: String?

    private let worker = BenchmarkWorker()
    private weak var eventLog: HardwareEventLog?
    private var benchmarkTask: Task<BenchmarkMeasurement, Error>?
    private var advancedBenchmarkTask: Task<AdvancedBenchmarkResult, Error>?

    func cancel() {
        benchmarkTask?.cancel()
        advancedBenchmarkTask?.cancel()
    }

    func attachEventLog(_ eventLog: HardwareEventLog) {
        self.eventLog = eventLog
    }

    func runBenchmark(mountPath: String, config: BenchmarkConfig) async throws -> BenchmarkResult {
        isRunning = true
        progress = 0
        errorMessage = nil
        lastResult = nil
        currentPhase = "Preparazione…"
        eventLog?.recordBenchmark(kind: .benchmarkStarted, mountPath: mountPath)
        defer { benchmarkTask = nil; isRunning = false }

        do {
            benchmarkTask = Task { [worker] in
                try await worker.run(mountPath: mountPath, testSizeBytes: config.testSizeBytes) { [weak self] update in
                    await self?.apply(update)
                }
            }
            let measurement = try await benchmarkTask!.value
            let result = BenchmarkResult(
                sequentialReadMBps: measurement.sequentialReadMBps,
                sequentialWriteMBps: measurement.sequentialWriteMBps,
                testSizeBytes: config.testSizeBytes,
                durationSeconds: measurement.durationSeconds
            )
            lastResult = result
            progress = 1
            currentPhase = "Completato"
            eventLog?.recordBenchmark(kind: .benchmarkCompleted, mountPath: mountPath)
            return result
        } catch is CancellationError {
            currentPhase = "Annullato"
            errorMessage = BenchmarkError.cancelled.errorDescription
            eventLog?.recordBenchmark(kind: .benchmarkFailed, mountPath: mountPath, detail: errorMessage)
            throw BenchmarkError.cancelled
        } catch {
            currentPhase = "Interrotto"
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            eventLog?.recordBenchmark(kind: .benchmarkFailed, mountPath: mountPath, detail: errorMessage)
            throw error
        }
    }

    func runAdvancedBenchmark(
        mountPath: String,
        configuration: AdvancedBenchmarkConfiguration,
        freeBytes: UInt64,
        volumeCapacityBytes: UInt64,
        userConfirmedExtendedTest: Bool
    ) async throws -> AdvancedBenchmarkResult {
        let decision = BenchmarkSafetyPolicy.decision(
            preset: configuration.preset,
            freeBytes: freeBytes,
            volumeCapacityBytes: volumeCapacityBytes,
            userConfirmedExtendedTest: userConfirmedExtendedTest
        )
        switch decision {
        case .allowed:
            break
        case .requiresConfirmation:
            throw BenchmarkError.extendedTestConfirmationRequired
        case .insufficientSpace(let requiredBytes):
            throw BenchmarkError.insufficientSpaceWithReserve(requiredBytes)
        }

        isRunning = true
        progress = 0
        errorMessage = nil
        lastAdvancedResult = nil
        currentPhase = "Preparazione…"
        eventLog?.recordBenchmark(kind: .benchmarkStarted, mountPath: mountPath)
        defer { advancedBenchmarkTask = nil; isRunning = false }

        do {
            let requiredFreeBytes = BenchmarkSafetyPolicy.requiredFreeBytes(
                for: configuration.preset,
                volumeCapacityBytes: volumeCapacityBytes
            )
            advancedBenchmarkTask = Task { [worker] in
                try await worker.runAdvanced(
                    mountPath: mountPath,
                    configuration: configuration,
                    requiredFreeBytes: requiredFreeBytes
                ) { [weak self] update in
                    await self?.apply(update)
                }
            }
            let completed = try await advancedBenchmarkTask!.value
            lastAdvancedResult = completed
            progress = 1
            currentPhase = "Completato"
            eventLog?.recordBenchmark(kind: .benchmarkCompleted, mountPath: mountPath)
            return completed
        } catch is CancellationError {
            currentPhase = "Annullato"
            errorMessage = BenchmarkError.cancelled.errorDescription
            eventLog?.recordBenchmark(kind: .benchmarkFailed, mountPath: mountPath, detail: errorMessage)
            throw BenchmarkError.cancelled
        } catch {
            currentPhase = "Interrotto"
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            eventLog?.recordBenchmark(kind: .benchmarkFailed, mountPath: mountPath, detail: errorMessage)
            throw error
        }
    }

    private func apply(_ update: BenchmarkProgress) {
        progress = update.fractionCompleted
        currentPhase = switch update.phase {
        case .preparing: "Preparazione…"
        case .writing: "Scrittura in corso…"
        case .reading: "Lettura in corso…"
        case .finished: "Completato"
        }
    }
}
