import Foundation
import IOKit
import CoreGraphics
import CAVICore

@Observable
@MainActor
public final class EDIDReaderService {
    public private(set) var parsedEDIDs: [CGDirectDisplayID: CAVICore.ParsedEDID] = [:]
    private var rawEDIDs: [CGDirectDisplayID: [UInt8]] = [:]
    /// Displays whose EDID could not be found. Cached so the view does not rescan the registry on every redraw.
    private var unavailableDisplayIDs: Set<CGDirectDisplayID> = []

    public init() {}

    public func readEDID(for displayID: CGDirectDisplayID) -> CAVICore.ParsedEDID? {
        if let parsed = parsedEDIDs[displayID] { return parsed }
        guard !unavailableDisplayIDs.contains(displayID) else { return nil }

        let vendor = CGDisplayVendorNumber(displayID)
        let product = CGDisplayModelNumber(displayID)
        guard let bytes = legacyEDIDBytes(vendor: vendor, product: product) ?? registryEDIDBytes(vendor: vendor, product: product),
              let edid = EDIDParser.parse(bytes)
        else {
            unavailableDisplayIDs.insert(displayID)
            return nil
        }

        rawEDIDs[displayID] = bytes
        parsedEDIDs[displayID] = edid
        return edid
    }

    public func parsedEDID(for displayID: CGDirectDisplayID) -> CAVICore.ParsedEDID? {
        readEDID(for: displayID)
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

    /// Older Intel Macs expose the EDID on `IODisplayConnect` services.
    private func legacyEDIDBytes(vendor: UInt32, product: UInt32) -> [UInt8]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            let vendorInfo = IORegistryEntryCreateCFProperty(service, kDisplayVendorID as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? UInt32
            let productInfo = IORegistryEntryCreateCFProperty(service, kDisplayProductID as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? UInt32
            guard vendorInfo == vendor, productInfo == product,
                  let data = IORegistryEntryCreateCFProperty(service, "IODisplayEDID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                  Self.isEDIDMatching([UInt8](data), vendor: vendor, product: product)
            else { continue }
            return [UInt8](data)
        }
        return nil
    }

    /// Apple silicon Macs expose the EDID as an `EDID` property on the display transport nodes.
    private func registryEDIDBytes(vendor: UInt32, product: UInt32) -> [UInt8]? {
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let data = IORegistryEntryCreateCFProperty(entry, "EDID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data
            IOObjectRelease(entry)
            if let data, Self.isEDIDMatching([UInt8](data), vendor: vendor, product: product) {
                return [UInt8](data)
            }
            entry = IOIteratorNext(iterator)
        }
        return nil
    }

    /// Checks the EDID header and that its manufacturer and product code match the display reported by CoreGraphics.
    static func isEDIDMatching(_ bytes: [UInt8], vendor: UInt32, product: UInt32) -> Bool {
        guard bytes.count >= 128,
              Array(bytes[0..<8]) == [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        else { return false }
        let manufacturer = UInt32(bytes[8]) << 8 | UInt32(bytes[9])
        let productCode = UInt32(bytes[10]) | UInt32(bytes[11]) << 8
        return manufacturer == vendor && productCode == product
    }
}
