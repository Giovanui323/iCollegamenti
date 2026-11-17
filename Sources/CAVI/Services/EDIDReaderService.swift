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
    /// Bookkeeping only; views do not need to redraw when it changes.
    @ObservationIgnored private var pendingDisplayIDs: Set<CGDirectDisplayID> = []

    public init() {}

    public func readEDID(for displayID: CGDirectDisplayID) -> CAVICore.ParsedEDID? {
        if let parsed = parsedEDIDs[displayID] { return parsed }
        guard !unavailableDisplayIDs.contains(displayID) else { return nil }

        let vendor = CGDisplayVendorNumber(displayID)
        let product = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        guard let bytes = legacyEDIDBytes(vendor: vendor, product: product, serial: serial)
                ?? registryEDIDBytes(vendor: vendor, product: product, serial: serial),
              let edid = EDIDParser.parse(bytes)
        else {
            unavailableDisplayIDs.insert(displayID)
            return nil
        }

        rawEDIDs[displayID] = bytes
        parsedEDIDs[displayID] = edid
        return edid
    }

    /// Safe to call from a view body: it only reads the cache. A missing entry is loaded on the
    /// next main-actor turn, because changing observed state while SwiftUI is drawing a view
    /// makes it redraw again mid-update and the tabs could stall.
    public func parsedEDID(for displayID: CGDirectDisplayID) -> CAVICore.ParsedEDID? {
        if let parsed = parsedEDIDs[displayID] { return parsed }
        if !unavailableDisplayIDs.contains(displayID) && !pendingDisplayIDs.contains(displayID) {
            pendingDisplayIDs.insert(displayID)
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = self.readEDID(for: displayID)
                self.pendingDisplayIDs.remove(displayID)
            }
        }
        return nil
    }

    /// Called when the display configuration changes. A display whose EDID was not yet published
    /// in the I/O Registry right after hot-plug is retried, instead of staying "unavailable" forever.
    public func readAllEDIDs(displayIDs: [CGDirectDisplayID]) {
        unavailableDisplayIDs.subtract(displayIDs)
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
    private func legacyEDIDBytes(vendor: UInt32, product: UInt32, serial: UInt32) -> [UInt8]? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var candidates: [[UInt8]] = []
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
            candidates.append([UInt8](data))
        }
        return Self.preferredEDID(candidates, serial: serial)
    }

    /// Apple silicon Macs expose the EDID as an `EDID` property on the display transport nodes.
    private func registryEDIDBytes(vendor: UInt32, product: UInt32, serial: UInt32) -> [UInt8]? {
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var candidates: [[UInt8]] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            let data = IORegistryEntryCreateCFProperty(entry, "EDID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data
            IOObjectRelease(entry)
            if let data, Self.isEDIDMatching([UInt8](data), vendor: vendor, product: product) {
                let bytes = [UInt8](data)
                // The serial is the only thing that tells two monitors of the same model apart.
                if serial != 0, Self.edidSerial(bytes) == serial { return bytes }
                candidates.append(bytes)
            }
            entry = IOIteratorNext(iterator)
        }
        return Self.preferredEDID(candidates, serial: serial)
    }

    /// Two identical monitors share vendor and product codes; returning the first match gave both
    /// the same EDID. Prefer the one whose serial matches what CoreGraphics reports.
    nonisolated static func preferredEDID(_ candidates: [[UInt8]], serial: UInt32) -> [UInt8]? {
        if serial != 0, let exact = candidates.first(where: { edidSerial($0) == serial }) { return exact }
        return candidates.first
    }

    nonisolated static func edidSerial(_ bytes: [UInt8]) -> UInt32? {
        guard bytes.count >= 16 else { return nil }
        return UInt32(bytes[12]) | UInt32(bytes[13]) << 8 | UInt32(bytes[14]) << 16 | UInt32(bytes[15]) << 24
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
