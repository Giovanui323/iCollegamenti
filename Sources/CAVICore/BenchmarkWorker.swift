import Foundation
import Darwin
import CryptoKit

public enum BenchmarkError: Error, LocalizedError, Equatable {
    case volumeNotWritable, insufficientSpace, insufficientSpaceWithReserve(UInt64), extendedTestConfirmationRequired, fileIOError(String), cancelled, invalidPath
    public var errorDescription: String? {
        switch self {
        case .volumeNotWritable: "Il volume è in sola lettura o non è scrivibile."
        case .insufficientSpace: "Spazio insufficiente: servono almeno il doppio dei dati del test."
        case .insufficientSpaceWithReserve(let requiredBytes):
            "Spazio insufficiente: per questo test servono almeno \(ByteCountFormatter.string(fromByteCount: Int64(requiredBytes), countStyle: .file)) liberi."
        case .extendedTestConfirmationRequired:
            "I test da 50 GB e 100 GB richiedono una conferma esplicita."
        case .fileIOError(let message): "Errore di input/output: \(message)"
        case .cancelled: "Benchmark annullato."
        case .invalidPath: "Percorso del volume non valido."
        }
    }
}

public struct BenchmarkMeasurement: Sendable { public let sequentialReadMBps, sequentialWriteMBps, durationSeconds: Double }
public enum BenchmarkPhase: String, Sendable { case preparing, writing, reading, finished }
public struct BenchmarkProgress: Sendable {
    public let phase: BenchmarkPhase
    public let fractionCompleted: Double
    public init(phase: BenchmarkPhase, fractionCompleted: Double) {
        self.phase = phase
        self.fractionCompleted = fractionCompleted
    }
}
public struct BenchmarkWorker: Sendable {
    public init() {}
    public func run(mountPath: String, testSizeBytes: UInt64, progress: @Sendable (BenchmarkProgress) async -> Void = { _ in }) async throws -> BenchmarkMeasurement {
        await progress(.init(phase: .preparing, fractionCompleted: 0))
        let fm = FileManager.default; var isDirectory = ObjCBool(false)
        guard fm.fileExists(atPath: mountPath, isDirectory: &isDirectory), isDirectory.boolValue else { throw BenchmarkError.invalidPath }
        guard let free = try fm.attributesOfFileSystem(forPath: mountPath)[.systemFreeSize] as? NSNumber else { throw BenchmarkError.invalidPath }
        guard free.uint64Value >= testSizeBytes * 2 else { throw BenchmarkError.insufficientSpace }
        let path = (mountPath as NSString).appendingPathComponent(".cavi-benchmark-\(UUID().uuidString).bin")
        defer { try? fm.removeItem(atPath: path) }
        let size = 1_048_576, buffer = [UInt8](repeating: 0xAA, count: size); let started = Date()
        let writeStart = CFAbsoluteTimeGetCurrent(), writeFD = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard writeFD != -1 else { throw BenchmarkError.volumeNotWritable }; defer { close(writeFD) }; _ = fcntl(writeFD, F_NOCACHE, 1)
        var written: UInt64 = 0
        while written < testSizeBytes { try Task.checkCancellation(); let count = Int(min(UInt64(size), testSizeBytes - written)); let result = write(writeFD, buffer, count); guard result > 0 else { throw BenchmarkError.fileIOError(result == 0 ? "Scrittura incompleta" : String(cString: strerror(errno))) }; written += UInt64(result); await progress(.init(phase: .writing, fractionCompleted: Double(written) / Double(testSizeBytes) * 0.5)) }
        guard fsync(writeFD) == 0 else { throw BenchmarkError.fileIOError(String(cString: strerror(errno))) }
        let writeDuration = CFAbsoluteTimeGetCurrent() - writeStart
        let readFD = open(path, O_RDONLY); guard readFD != -1 else { throw BenchmarkError.fileIOError(String(cString: strerror(errno))) }; defer { close(readFD) }; _ = fcntl(readFD, F_NOCACHE, 1)
        var readBuffer = [UInt8](repeating: 0, count: size), readTotal: UInt64 = 0; let readStart = CFAbsoluteTimeGetCurrent()
        while readTotal < testSizeBytes { try Task.checkCancellation(); let count = Int(min(UInt64(size), testSizeBytes - readTotal)); let result = read(readFD, &readBuffer, count); guard result > 0 else { throw BenchmarkError.fileIOError(result == 0 ? "Lettura incompleta" : String(cString: strerror(errno))) }; readTotal += UInt64(result); await progress(.init(phase: .reading, fractionCompleted: 0.5 + Double(readTotal) / Double(testSizeBytes) * 0.5)) }
        let readDuration = CFAbsoluteTimeGetCurrent() - readStart
        await progress(.init(phase: .finished, fractionCompleted: 1))
        return .init(sequentialReadMBps: Double(readTotal) / readDuration / 1_000_000, sequentialWriteMBps: Double(written) / writeDuration / 1_000_000, durationSeconds: Date().timeIntervalSince(started))
    }
}

public extension BenchmarkWorker {
    /// Runs an advanced workload against an exclusive `.cavi-benchmark-*`
    /// temporary file. `testSizeBytes` is an internal/testing override; app
    /// callers use the preset's fixed size after applying `BenchmarkSafetyPolicy`.
    func runAdvanced(
        mountPath: String,
        configuration: AdvancedBenchmarkConfiguration,
        testSizeBytes: UInt64? = nil,
        requiredFreeBytes: UInt64? = nil,
        progress: @Sendable (BenchmarkProgress) async -> Void = { _ in }
    ) async throws -> AdvancedBenchmarkResult {
        await progress(.init(phase: .preparing, fractionCompleted: 0))
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: mountPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BenchmarkError.invalidPath
        }

        let byteCount = testSizeBytes ?? configuration.preset.sizeBytes
        guard byteCount > 0 else { throw BenchmarkError.invalidPath }
        let requiredSpace = requiredFreeBytes ?? byteCount * 2
        guard let free = try fileManager.attributesOfFileSystem(forPath: mountPath)[.systemFreeSize] as? NSNumber,
              free.uint64Value >= requiredSpace else {
            throw BenchmarkError.insufficientSpace
        }

        let path = (mountPath as NSString).appendingPathComponent(".cavi-benchmark-\(UUID().uuidString).bin")
        defer { try? fileManager.removeItem(atPath: path) }

        let fd = open(path, O_RDWR | O_CREAT | O_EXCL, 0o600)
        guard fd != -1 else { throw BenchmarkError.volumeNotWritable }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)

        let result: AdvancedBenchmarkResult
        switch configuration.workload {
        case .sequential:
            result = try await sequentialResult(
                fd: fd,
                byteCount: byteCount,
                configuration: configuration,
                progress: progress
            )
        case .sustainedWrite, .stress:
            result = try await sustainedWriteResult(
                fd: fd,
                byteCount: byteCount,
                configuration: configuration,
                progress: progress
            )
        case .random4KRead:
            result = try await randomResult(
                fd: fd,
                byteCount: byteCount,
                configuration: configuration,
                isWrite: false,
                progress: progress
            )
        case .random4KWrite:
            result = try await randomResult(
                fd: fd,
                byteCount: byteCount,
                configuration: configuration,
                isWrite: true,
                progress: progress
            )
        case .mixedReadWrite:
            result = try await mixedResult(
                fd: fd,
                byteCount: byteCount,
                configuration: configuration,
                progress: progress
            )
        case .latency:
            result = try await latencyResult(
                fd: fd,
                byteCount: byteCount,
                configuration: configuration,
                progress: progress
            )
        case .integrity:
            result = try await integrityResult(
                fd: fd,
                byteCount: byteCount,
                configuration: configuration,
                progress: progress
            )
        }

        await progress(.init(phase: .finished, fractionCompleted: 1))
        return result
    }

    private func sequentialResult(
        fd: Int32,
        byteCount: UInt64,
        configuration: AdvancedBenchmarkConfiguration,
        progress: @Sendable (BenchmarkProgress) async -> Void
    ) async throws -> AdvancedBenchmarkResult {
        let blockSize = BenchmarkWorkload.sequential.blockSizeBytes
        let writeStarted = CFAbsoluteTimeGetCurrent()
        try await writeSequential(fd: fd, byteCount: byteCount, blockSize: blockSize, seed: configuration.seed, progress: progress)
        let writeDuration = max(CFAbsoluteTimeGetCurrent() - writeStarted, 0.000_001)
        let readStarted = CFAbsoluteTimeGetCurrent()
        try await readSequential(fd: fd, byteCount: byteCount, blockSize: blockSize, progress: progress)
        let readDuration = max(CFAbsoluteTimeGetCurrent() - readStarted, 0.000_001)
        return AdvancedBenchmarkResult(
            configuration: configuration,
            samples: [BenchmarkSample(
                transferredBytes: byteCount,
                readMBps: Double(byteCount) / readDuration / 1_000_000,
                writeMBps: Double(byteCount) / writeDuration / 1_000_000
            )]
        )
    }

    private func sustainedWriteResult(
        fd: Int32,
        byteCount: UInt64,
        configuration: AdvancedBenchmarkConfiguration,
        progress: @Sendable (BenchmarkProgress) async -> Void
    ) async throws -> AdvancedBenchmarkResult {
        let blockSize = BenchmarkWorkload.sustainedWrite.blockSizeBytes
        let started = CFAbsoluteTimeGetCurrent()
        var samples: [BenchmarkSample] = []
        var totalWritten: UInt64 = 0
        var random = BenchmarkRandom(seed: configuration.seed)
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var lastSample = started
        var stressOffset: UInt64 = 0
        let isStressTest = configuration.workload == .stress

        // A stress test transfers data repeatedly, but it never grows the
        // exclusive temporary file past the preset quota.
        if isStressTest, ftruncate(fd, off_t(byteCount)) != 0 {
            throw ioError()
        }

        while totalWritten < byteCount || shouldContinueStress(configuration: configuration, started: started) {
            try Task.checkCancellation()
            random.fill(&buffer)
            let count: Int
            if isStressTest {
                count = Int(min(UInt64(blockSize), byteCount - stressOffset))
                try positionedWriteAll(fd: fd, bytes: buffer, count: count, offset: off_t(stressOffset))
                stressOffset = (stressOffset + UInt64(count)) % byteCount
            } else {
                count = Int(min(UInt64(blockSize), byteCount - totalWritten))
                try writeAll(fd: fd, bytes: buffer, count: count)
            }
            totalWritten += UInt64(count)
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastSample >= 1 {
                let elapsed = max(now - started, 0.000_001)
                samples.append(BenchmarkSample(
                    transferredBytes: totalWritten,
                    writeMBps: Double(totalWritten) / elapsed / 1_000_000
                ))
                lastSample = now
            }
            await progress(.init(phase: .writing, fractionCompleted: min(Double(totalWritten) / Double(byteCount), 0.99)))
            if !isStressTest && totalWritten >= byteCount { break }
        }
        guard fsync(fd) == 0 else { throw ioError() }
        if samples.last?.transferredBytes != totalWritten {
            let elapsed = max(CFAbsoluteTimeGetCurrent() - started, 0.000_001)
            samples.append(BenchmarkSample(
                transferredBytes: totalWritten,
                writeMBps: Double(totalWritten) / elapsed / 1_000_000
            ))
        }
        return AdvancedBenchmarkResult(configuration: configuration, samples: samples)
    }

    private func randomResult(
        fd: Int32,
        byteCount: UInt64,
        configuration: AdvancedBenchmarkConfiguration,
        isWrite: Bool,
        progress: @Sendable (BenchmarkProgress) async -> Void
    ) async throws -> AdvancedBenchmarkResult {
        let blockSize = configuration.effectiveBlockSizeBytes
        let alignedByteCount = max(UInt64(blockSize), byteCount / UInt64(blockSize) * UInt64(blockSize))
        if !isWrite {
            try await writeSequential(
                fd: fd,
                byteCount: alignedByteCount,
                blockSize: blockSize,
                seed: configuration.seed,
                progress: progress
            )
        } else if ftruncate(fd, off_t(alignedByteCount)) != 0 {
            throw ioError()
        }

        var random = BenchmarkRandom(seed: configuration.seed)
        var buffer = [UInt8](repeating: 0, count: blockSize)
        let operationCount = Int(alignedByteCount / UInt64(blockSize))
        let started = CFAbsoluteTimeGetCurrent()
        var samples: [BenchmarkSample] = []

        for operation in 0..<operationCount {
            try Task.checkCancellation()
            let offset = off_t(random.next() % UInt64(operationCount) * UInt64(blockSize))
            if isWrite {
                random.fill(&buffer)
                try positionedWriteAll(fd: fd, bytes: buffer, offset: offset)
            } else {
                try positionedReadAll(fd: fd, bytes: &buffer, offset: offset)
            }
            if operation == operationCount - 1 || operation.isMultiple(of: 256) {
                let elapsed = max(CFAbsoluteTimeGetCurrent() - started, 0.000_001)
                let completedBytes = UInt64(operation + 1) * UInt64(blockSize)
                let throughput = Double(completedBytes) / elapsed / 1_000_000
                samples.append(BenchmarkSample(
                    transferredBytes: completedBytes,
                    readMBps: isWrite ? nil : throughput,
                    writeMBps: isWrite ? throughput : nil
                ))
                await progress(.init(phase: isWrite ? .writing : .reading, fractionCompleted: Double(operation + 1) / Double(operationCount)))
            }
        }
        if isWrite, fsync(fd) != 0 { throw ioError() }
        let elapsed = max(CFAbsoluteTimeGetCurrent() - started, 0.000_001)
        let iops = Double(operationCount) / elapsed
        return AdvancedBenchmarkResult(
            configuration: configuration,
            samples: samples,
            randomReadIOPS: isWrite ? nil : iops,
            randomWriteIOPS: isWrite ? iops : nil
        )
    }

    private func mixedResult(
        fd: Int32,
        byteCount: UInt64,
        configuration: AdvancedBenchmarkConfiguration,
        progress: @Sendable (BenchmarkProgress) async -> Void
    ) async throws -> AdvancedBenchmarkResult {
        let blockSize = configuration.effectiveBlockSizeBytes
        let alignedByteCount = max(UInt64(blockSize * 2), byteCount / UInt64(blockSize * 2) * UInt64(blockSize * 2))
        try await writeSequential(fd: fd, byteCount: alignedByteCount, blockSize: blockSize, seed: configuration.seed, progress: progress)
        var random = BenchmarkRandom(seed: configuration.seed ^ 0xBAD5_EED)
        var writeBuffer = [UInt8](repeating: 0, count: blockSize)
        var readBuffer = [UInt8](repeating: 0, count: blockSize)
        let operations = Int(alignedByteCount / UInt64(blockSize * 2))
        let started = CFAbsoluteTimeGetCurrent()

        for index in 0..<operations {
            try Task.checkCancellation()
            random.fill(&writeBuffer)
            let writeOffset = off_t(UInt64(index) * UInt64(blockSize))
            let readOffset = off_t(alignedByteCount / 2 + UInt64(index) * UInt64(blockSize))
            try positionedWriteAll(fd: fd, bytes: writeBuffer, offset: writeOffset)
            try positionedReadAll(fd: fd, bytes: &readBuffer, offset: readOffset)
            if index.isMultiple(of: 256) || index == operations - 1 {
                await progress(.init(phase: .writing, fractionCompleted: Double(index + 1) / Double(operations)))
            }
        }
        guard fsync(fd) == 0 else { throw ioError() }
        let elapsed = max(CFAbsoluteTimeGetCurrent() - started, 0.000_001)
        let half = Double(alignedByteCount / 2) / elapsed / 1_000_000
        return AdvancedBenchmarkResult(
            configuration: configuration,
            samples: [BenchmarkSample(transferredBytes: alignedByteCount, readMBps: half, writeMBps: half)]
        )
    }

    private func latencyResult(
        fd: Int32,
        byteCount: UInt64,
        configuration: AdvancedBenchmarkConfiguration,
        progress: @Sendable (BenchmarkProgress) async -> Void
    ) async throws -> AdvancedBenchmarkResult {
        let blockSize = BenchmarkWorkload.latency.blockSizeBytes
        let alignedByteCount = max(UInt64(blockSize), byteCount / UInt64(blockSize) * UInt64(blockSize))
        try await writeSequential(fd: fd, byteCount: alignedByteCount, blockSize: blockSize, seed: configuration.seed, progress: progress)
        var buffer = [UInt8](repeating: 0, count: blockSize)
        let operations = Int(alignedByteCount / UInt64(blockSize))
        var latencies: [Double] = []

        for index in 0..<operations {
            try Task.checkCancellation()
            let started = CFAbsoluteTimeGetCurrent()
            try positionedReadAll(fd: fd, bytes: &buffer, offset: off_t(index * blockSize))
            latencies.append((CFAbsoluteTimeGetCurrent() - started) * 1_000)
            if index.isMultiple(of: 256) || index == operations - 1 {
                await progress(.init(phase: .reading, fractionCompleted: Double(index + 1) / Double(operations)))
            }
        }

        return AdvancedBenchmarkResult(
            configuration: configuration,
            samples: [BenchmarkSample(transferredBytes: alignedByteCount, latencyMilliseconds: AnalysisMetrics.median(latencies))],
            latencyMinimumMilliseconds: latencies.min(),
            latencyAverageMilliseconds: AnalysisMetrics.average(latencies),
            latencyMaximumMilliseconds: latencies.max(),
            latencyP95Milliseconds: AnalysisMetrics.percentile(latencies, fraction: 0.95),
            latencyP99Milliseconds: AnalysisMetrics.percentile(latencies, fraction: 0.99)
        )
    }

    private func integrityResult(
        fd: Int32,
        byteCount: UInt64,
        configuration: AdvancedBenchmarkConfiguration,
        progress: @Sendable (BenchmarkProgress) async -> Void
    ) async throws -> AdvancedBenchmarkResult {
        let blockSize = BenchmarkWorkload.integrity.blockSizeBytes
        var random = BenchmarkRandom(seed: configuration.seed)
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var writeHash = SHA256()
        var written: UInt64 = 0

        while written < byteCount {
            try Task.checkCancellation()
            let count = Int(min(UInt64(blockSize), byteCount - written))
            random.fill(&buffer)
            try writeAll(fd: fd, bytes: buffer, count: count)
            writeHash.update(data: Data(buffer.prefix(count)))
            written += UInt64(count)
            await progress(.init(phase: .writing, fractionCompleted: Double(written) / Double(byteCount) * 0.5))
        }
        guard fsync(fd) == 0 else { throw ioError() }

        guard lseek(fd, 0, SEEK_SET) != -1 else { throw ioError() }
        var readHash = SHA256()
        var read: UInt64 = 0
        while read < byteCount {
            try Task.checkCancellation()
            let count = Int(min(UInt64(blockSize), byteCount - read))
            try readAll(fd: fd, bytes: &buffer, count: count)
            readHash.update(data: Data(buffer.prefix(count)))
            read += UInt64(count)
            await progress(.init(phase: .reading, fractionCompleted: 0.5 + Double(read) / Double(byteCount) * 0.5))
        }

        let passed = writeHash.finalize() == readHash.finalize()
        return AdvancedBenchmarkResult(
            configuration: configuration,
            samples: [BenchmarkSample(transferredBytes: byteCount)],
            integrityPassed: passed,
            bytesVerified: passed ? byteCount : nil,
            errorCount: passed ? 0 : 1
        )
    }

    private func writeSequential(
        fd: Int32,
        byteCount: UInt64,
        blockSize: Int,
        seed: UInt64,
        progress: @Sendable (BenchmarkProgress) async -> Void
    ) async throws {
        guard lseek(fd, 0, SEEK_SET) != -1 else { throw ioError() }
        var random = BenchmarkRandom(seed: seed)
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var written: UInt64 = 0
        while written < byteCount {
            try Task.checkCancellation()
            let count = Int(min(UInt64(blockSize), byteCount - written))
            random.fill(&buffer)
            try writeAll(fd: fd, bytes: buffer, count: count)
            written += UInt64(count)
            await progress(.init(phase: .writing, fractionCompleted: Double(written) / Double(byteCount) * 0.5))
        }
        guard fsync(fd) == 0 else { throw ioError() }
    }

    private func readSequential(
        fd: Int32,
        byteCount: UInt64,
        blockSize: Int,
        progress: @Sendable (BenchmarkProgress) async -> Void
    ) async throws {
        guard lseek(fd, 0, SEEK_SET) != -1 else { throw ioError() }
        var buffer = [UInt8](repeating: 0, count: blockSize)
        var read: UInt64 = 0
        while read < byteCount {
            try Task.checkCancellation()
            let count = Int(min(UInt64(blockSize), byteCount - read))
            try readAll(fd: fd, bytes: &buffer, count: count)
            read += UInt64(count)
            await progress(.init(phase: .reading, fractionCompleted: 0.5 + Double(read) / Double(byteCount) * 0.5))
        }
    }

    private func shouldContinueStress(configuration: AdvancedBenchmarkConfiguration, started: CFAbsoluteTime) -> Bool {
        guard configuration.workload == .stress,
              let duration = configuration.stressDurationSeconds,
              duration > 0 else {
            return false
        }
        return CFAbsoluteTimeGetCurrent() - started < duration
    }

    private func writeAll(fd: Int32, bytes: [UInt8], count: Int) throws {
        var offset = 0
        while offset < count {
            let result = bytes.withUnsafeBytes { buffer in
                write(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
            }
            guard result > 0 else { throw ioError(result) }
            offset += result
        }
    }

    private func readAll(fd: Int32, bytes: inout [UInt8], count: Int) throws {
        var offset = 0
        while offset < count {
            let result = bytes.withUnsafeMutableBytes { buffer in
                read(fd, buffer.baseAddress!.advanced(by: offset), count - offset)
            }
            guard result > 0 else { throw ioError(result) }
            offset += result
        }
    }

    private func positionedWriteAll(fd: Int32, bytes: [UInt8], count: Int? = nil, offset: off_t) throws {
        var written = 0
        let byteCount = count ?? bytes.count
        while written < byteCount {
            let result = bytes.withUnsafeBytes { buffer in
                pwrite(fd, buffer.baseAddress!.advanced(by: written), byteCount - written, offset + off_t(written))
            }
            guard result > 0 else { throw ioError(result) }
            written += result
        }
    }

    private func positionedReadAll(fd: Int32, bytes: inout [UInt8], offset: off_t) throws {
        var read = 0
        let byteCount = bytes.count
        while read < byteCount {
            let result = bytes.withUnsafeMutableBytes { buffer in
                pread(fd, buffer.baseAddress!.advanced(by: read), byteCount - read, offset + off_t(read))
            }
            guard result > 0 else { throw ioError(result) }
            read += result
        }
    }

    private func ioError(_ result: Int = -1) -> BenchmarkError {
        BenchmarkError.fileIOError(result == 0 ? "Operazione incompleta" : String(cString: strerror(errno)))
    }
}

private struct BenchmarkRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func fill(_ bytes: inout [UInt8]) {
        var value: UInt64 = 0
        for index in bytes.indices {
            if index.isMultiple(of: MemoryLayout<UInt64>.size) {
                value = next()
            }
            bytes[index] = UInt8(truncatingIfNeeded: value >> ((index % MemoryLayout<UInt64>.size) * 8))
        }
    }
}
