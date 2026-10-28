import Foundation

/// Runs a command-line tool with a time limit.
///
/// Output is read while the process runs. Waiting for the process to exit before reading a pipe can deadlock once
/// the pipe buffer fills, and a tool that hangs would otherwise block the caller for good.
enum BoundedProcess {
    struct Result {
        let status: Int32
        let output: Data
        let timedOut: Bool
    }

    /// Output buffer shared with the reader thread. Written once, read only after the reader signals completion.
    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    /// Returns nil only when the tool cannot be launched.
    static func run(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval,
        mergeStandardError: Bool = false
    ) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = mergeStandardError ? stdout : FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let box = OutputBox()
        let finished = DispatchSemaphore(value: 0)
        let reader = stdout.fileHandleForReading
        DispatchQueue.global(qos: .utility).async {
            box.data = reader.readDataToEndOfFile()
            finished.signal()
        }

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            // Once the process is gone the pipe closes and the reader finishes. Bounded, in case a child keeps it open.
            _ = finished.wait(timeout: .now() + 2)
        }
        process.waitUntilExit()

        return Result(status: process.terminationStatus, output: box.data, timedOut: timedOut)
    }
}
