import DiskArbitration
import Foundation

private final class DiskArbitrationMountRequest {
    let session: DASession
    let disk: DADisk
    let bsdName: String
    let continuation: CheckedContinuation<Void, Error>

    init(session: DASession, disk: DADisk, bsdName: String, continuation: CheckedContinuation<Void, Error>) {
        self.session = session
        self.disk = disk
        self.bsdName = bsdName
        self.continuation = continuation
    }
}

enum DiskArbitrationMountService {
    static func mount(partitionBSDName: String) async throws {
        let bsdName = sanitizedBSDName(partitionBSDName)
        guard !bsdName.isEmpty, !isWholeDisk(bsdName) else {
            throw NSError(
                domain: "iCollegamenti",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Il mount richiede una partizione BSD valida, non un whole disk."]
            )
        }
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, "/dev/\(bsdName)") else {
            throw NSError(
                domain: "iCollegamenti",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: "Disk Arbitration non ha trovato la partizione \(bsdName)."]
            )
        }

        try await withCheckedThrowingContinuation { continuation in
            DASessionSetDispatchQueue(session, DispatchQueue.main)
            let request = Unmanaged.passRetained(
                DiskArbitrationMountRequest(session: session, disk: disk, bsdName: bsdName, continuation: continuation)
            )
            DADiskMount(
                disk,
                nil,
                DADiskMountOptions(kDADiskMountOptionDefault),
                mountCallback,
                request.toOpaque()
            )
        }
    }

    private static let mountCallback: DADiskMountCallback = { _, dissenter, context in
        guard let context else { return }
        let request = Unmanaged<DiskArbitrationMountRequest>.fromOpaque(context).takeRetainedValue()
        DASessionSetDispatchQueue(request.session, nil)
        guard let dissenter else {
            request.continuation.resume()
            return
        }
        let status = DADissenterGetStatus(dissenter)
        request.continuation.resume(throwing: NSError(
            domain: "DiskArbitration",
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "Disk Arbitration ha rifiutato il mount di \(request.bsdName) (status \(status))."]
        ))
    }

    static func mountWithDiskutilFallback(partitionBSDName: String) async throws {
        let bsdName = sanitizedBSDName(partitionBSDName)
        guard !bsdName.isEmpty, !isWholeDisk(bsdName) else {
            throw NSError(
                domain: "iCollegamenti",
                code: 12,
                userInfo: [NSLocalizedDescriptionKey: "Il fallback richiede una partizione BSD valida, non un whole disk."]
            )
        }
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["mount", bsdName]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let output = String(
                    data: pipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw NSError(
                    domain: "diskutil",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: output?.isEmpty == false ? output! : "diskutil non ha montato \(bsdName)."]
                )
            }
        }.value
    }

    private static func sanitizedBSDName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/dev/") ? String(trimmed.dropFirst(5)) : trimmed
    }

    private static func isWholeDisk(_ bsdName: String) -> Bool {
        bsdName.range(of: "^disk[0-9]+$", options: .regularExpression) != nil
    }
}
