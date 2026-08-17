import Foundation
import IOKit
import CoreGraphics
import CAVICore

@Observable
@MainActor
public final class EDIDReaderService {
    public private(set) var parsedEDIDs: [CGDirectDisplayID: CAVICore.ParsedEDID] = [:]
    private var rawEDIDs: [CGDirectDisplayID: [UInt8]] = [:]
    
    public init() {}
    
    public func readEDID(for displayID: CGDirectDisplayID) -> CAVICore.ParsedEDID? {
        let cgVendor = CGDisplayVendorNumber(displayID)
        let cgModel = CGDisplayModelNumber(displayID)
        
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator)
        if result == KERN_SUCCESS {
            var service = IOIteratorNext(iterator)
            while service != 0 {
                let vendorInfo = IORegistryEntryCreateCFProperty(service, kDisplayVendorID as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? UInt32
                let productInfo = IORegistryEntryCreateCFProperty(service, kDisplayProductID as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? UInt32
                
                if vendorInfo == cgVendor && productInfo == cgModel {
                    if let edidData = IORegistryEntryCreateCFProperty(service, "IODisplayEDID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
                        let bytes = [UInt8](edidData)
                        rawEDIDs[displayID] = bytes
                        if let edid = EDIDParser.parse(bytes) {
                            parsedEDIDs[displayID] = edid
                            IOObjectRelease(service)
                            IOObjectRelease(iterator)
                            return edid
                        }
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        return nil
    }
    
    public func parsedEDID(for displayID: CGDirectDisplayID) -> CAVICore.ParsedEDID? {
        return parsedEDIDs[displayID] ?? readEDID(for: displayID)
    }
    
    public func readAllEDIDs(displayIDs: [CGDirectDisplayID]) {
        for id in displayIDs {
            _ = readEDID(for: id)
        }
    }
    
    public func exportEDIDHex(for displayID: CGDirectDisplayID) -> String? {
        guard let bytes = rawEDIDs[displayID] else { return nil }
        var result = ""
        for i in stride(from: 0, to: bytes.count, by: 16) {
            let chunk = bytes[i..<min(i+16, bytes.count)]
            let hexStr = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            let paddedHex = hexStr.padding(toLength: 47, withPad: " ", startingAt: 0)
            let asciiStr = String(chunk.map { (c: UInt8) -> Character in
                return (c >= 32 && c <= 126) ? Character(UnicodeScalar(c)) : "."
            })
            result += String(format: "%04X: %@  |%@|\n", i, paddedHex, asciiStr)
        }
        return result
    }
}
