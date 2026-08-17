import Foundation
import IOKit
import DiskArbitration

/// Monitors real-time disk I/O throughput for external devices.
/// Polls IOBlockStorageDriver statistics to calculate current read/write MB/s.
@Observable
@MainActor
public final class DiskIOMonitorService {
    public var currentReadMBps: Double = 0.0
    public var currentWriteMBps: Double = 0.0
    public var maximumReadMBps: Double = 0.0
    public var maximumWriteMBps: Double = 0.0
    public var isMonitoring: Bool = false
    
    private var monitorTask: Task<Void, Never>?
    private var lastBytesRead: UInt64 = 0
    private var lastBytesWritten: UInt64 = 0
    private var lastSampleTime: CFAbsoluteTime = 0
    private var currentBSDName: String = ""
    
    public init() {}
    
    /// Start monitoring I/O for a specific device by BSD name (e.g. "disk7")
    public func startMonitoring(bsdName: String) {
        stopMonitoring()
        
        // Get the whole disk BSD name (e.g. "disk7" from "disk7s1")
        let wholeDisk = bsdName.replacingOccurrences(of: #"s\d+$"#, with: "", options: .regularExpression)
        currentBSDName = wholeDisk
        isMonitoring = true
        
        // Initialize counters
        if let stats = readDiskStatistics(bsdName: wholeDisk) {
            lastBytesRead = stats.bytesRead
            lastBytesWritten = stats.bytesWritten
            lastSampleTime = CFAbsoluteTimeGetCurrent()
        }
        
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.sample()
            }
        }
    }
    
    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        isMonitoring = false
        currentReadMBps = 0.0
        currentWriteMBps = 0.0
        maximumReadMBps = 0.0
        maximumWriteMBps = 0.0
    }
    
    private func sample() {
        guard isMonitoring else { return }
        
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastSampleTime
        guard elapsed > 0.1 else { return } // Avoid division by near-zero
        
        if let stats = readDiskStatistics(bsdName: currentBSDName) {
            let deltaRead = stats.bytesRead >= lastBytesRead ? stats.bytesRead - lastBytesRead : 0
            let deltaWrite = stats.bytesWritten >= lastBytesWritten ? stats.bytesWritten - lastBytesWritten : 0
            
            currentReadMBps = Double(deltaRead) / elapsed / 1_000_000.0
            currentWriteMBps = Double(deltaWrite) / elapsed / 1_000_000.0
            maximumReadMBps = max(maximumReadMBps, currentReadMBps)
            maximumWriteMBps = max(maximumWriteMBps, currentWriteMBps)
            
            lastBytesRead = stats.bytesRead
            lastBytesWritten = stats.bytesWritten
            lastSampleTime = now
        }
    }
    
    // MARK: - IOKit Disk Statistics
    
    private struct DiskStats {
        var bytesRead: UInt64
        var bytesWritten: UInt64
    }
    
    /// Reads cumulative bytes read/written from the IOBlockStorageDriver for a given BSD disk.
    private nonisolated func readDiskStatistics(bsdName: String) -> DiskStats? {
        let matchingDict = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName)
        var iterator: io_iterator_t = 0
        
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        
        var service = IOIteratorNext(iterator)
        while service != 0 {
            // Walk up to find IOBlockStorageDriver
            if let stats = findBlockStorageStats(from: service) {
                IOObjectRelease(service)
                return stats
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        
        return nil
    }
    
    /// Walks up the IORegistry tree from IOMedia to find IOBlockStorageDriver and read its Statistics.
    private nonisolated func findBlockStorageStats(from service: io_service_t) -> DiskStats? {
        var current = service
        IOObjectRetain(current)
        
        while current != 0 {
            var classNameBuf = [CChar](repeating: 0, count: 256)
            IOObjectGetClass(current, &classNameBuf)
            let className = classNameBuf.withUnsafeBufferPointer { buf in
                String(cString: buf.baseAddress!)
            }
            
            if className.contains("BlockStorageDriver") {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(current, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = props?.takeRetainedValue() as? [String: Any],
                   let statistics = dict["Statistics"] as? [String: Any] {
                    
                    let bytesRead = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                    let bytesWritten = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                    
                    IOObjectRelease(current)
                    return DiskStats(bytesRead: bytesRead, bytesWritten: bytesWritten)
                }
            }
            
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            if kr != KERN_SUCCESS { break }
            current = parent
        }
        
        return nil
    }
}
