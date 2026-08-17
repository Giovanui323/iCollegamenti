import Foundation
import IOKit
import CAVICore

/// Reads only the USB-C port-controller information that the local Mac has
/// already published in IOKit. It never sends identifiers away or writes to the
/// registry, and it treats unavailable properties as unavailable evidence.
@Observable
@MainActor
final class USBCableEvidenceDiscoveryService {
    private nonisolated static let controllerClasses = [
        "AppleHPMInterfaceType10",
        "AppleHPMInterfaceType11",
        "AppleHPMInterfaceType12",
        "AppleTCControllerType10",
        "AppleTCControllerType11",
        "IOPort"
    ]

    var snapshot = USBCableEvidenceBuilder.make(from: [])

    func refresh() {
        snapshot = Self.scan()
    }

    private nonisolated static func scan() -> USBCableEvidenceSnapshot {
        var seenEntries = Set<UInt64>()
        var records: [USBPortRegistryRecord] = []

        for className in controllerClasses {
            let matching = IOServiceMatching(className)
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }

            var service = IOIteratorNext(iterator)
            while service != 0 {
                let currentService = service
                defer { IOObjectRelease(currentService) }

                guard let properties = registryProperties(for: currentService),
                      isUSBPort(properties: properties),
                      let registryID = registryEntryID(for: currentService),
                      seenEntries.insert(registryID).inserted else {
                    service = IOIteratorNext(iterator)
                    continue
                }

                records.append(
                    USBPortRegistryRecord(
                        id: String(registryID),
                        portName: portName(properties: properties, fallback: className),
                        connectionActive: boolean(properties["ConnectionActive"])
                            ?? boolean(properties["IOAccessoryDetect"])
                            ?? false,
                        activeCable: boolean(properties["ActiveCable"]),
                        transports: stringArray(properties["TransportsActive"]),
                        authorizationRequired: boolean(properties["AuthorizationRequired"])
                            ?? boolean(properties["AuthenticationRequired"])
                            ?? false,
                        authorizationStatus: string(properties["UserAuthorizationStatusDescription"])
                            ?? string(properties["AuthorizationStatusDescription"]),
                        overcurrentCount: integer(properties["Overcurrent Count"]),
                        liquidDetected: boolean(properties["LDCM_LiquidDetected"]),
                        cableIdentityProperties: cableIdentityProperties(below: currentService)
                    )
                )

                service = IOIteratorNext(iterator)
            }
        }

        return USBCableEvidenceBuilder.make(from: records)
    }

    private nonisolated static func isUSBPort(properties: [String: Any]) -> Bool {
        string(properties["PortTypeDescription"])?.caseInsensitiveCompare("USB-C") == .orderedSame
    }

    private nonisolated static func portName(properties: [String: Any], fallback: String) -> String {
        string(properties["PortDescription"])
            ?? string(properties["Description"])
            ?? fallback
    }

    private nonisolated static func registryEntryID(for service: io_registry_entry_t) -> UInt64? {
        var identifier: UInt64 = 0
        guard IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS else { return nil }
        return identifier
    }

    private nonisolated static func registryProperties(for service: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else {
            return nil
        }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    private nonisolated static func cableIdentityProperties(below service: io_registry_entry_t) -> [String: String] {
        var result: [String: String] = [:]
        collectCableIdentityProperties(below: service, depth: 0, into: &result)
        return result
    }

    private nonisolated static func collectCableIdentityProperties(
        below entry: io_registry_entry_t,
        depth: Int,
        into result: inout [String: String]
    ) {
        guard depth < 5 else { return }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return
        }
        defer { IOObjectRelease(iterator) }

        var child = IOIteratorNext(iterator)
        while child != 0 {
            let currentChild = child
            defer { IOObjectRelease(currentChild) }

            let className = registryClassName(for: currentChild)
            if isCableIdentityComponent(className), let properties = registryProperties(for: currentChild) {
                for (key, value) in properties where isRelevantIdentityProperty(key) {
                    guard result.count < 16, let formatted = formattedRegistryValue(value) else { continue }
                    result["\(identityChannelName(for: className)).\(key)"] = formatted
                }
            }
            collectCableIdentityProperties(below: currentChild, depth: depth + 1, into: &result)
            child = IOIteratorNext(iterator)
        }
    }

    private nonisolated static func registryClassName(for entry: io_registry_entry_t) -> String {
        var name = [CChar](repeating: 0, count: 256)
        guard IOObjectGetClass(entry, &name) == KERN_SUCCESS else { return "Unknown" }
        return name.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    private nonisolated static func isCableIdentityComponent(_ className: String) -> Bool {
        className.contains("CCUSBPDSOPp") || className.contains("CCUSBPDSOPpp")
    }

    private nonisolated static func identityChannelName(for className: String) -> String {
        className.contains("SOPpp") ? "SOP''" : "SOP'"
    }

    private nonisolated static func isRelevantIdentityProperty(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return ["vdo", "identity", "vendor", "product", "vid", "pid", "cable", "current", "speed", "version", "active"]
            .contains { lowercased.contains($0) }
    }

    private nonisolated static func boolean(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool:
            value
        case let value as NSNumber:
            value.boolValue
        case let value as String:
            switch value.lowercased() {
            case "yes", "true", "1": true
            case "no", "false", "0": false
            default: nil
            }
        default:
            nil
        }
    }

    private nonisolated static func integer(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            value
        case let value as NSNumber:
            value.intValue
        case let value as String:
            Int(value)
        default:
            nil
        }
    }

    private nonisolated static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private nonisolated static func stringArray(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap(string).filter { !$0.isEmpty }
    }

    private nonisolated static func formattedRegistryValue(_ value: Any) -> String? {
        if let data = value as? Data {
            guard !data.isEmpty else { return nil }
            return data.map { String(format: "%02X", $0) }.joined()
        }
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let values = value as? [Any] {
            let formatted = values.compactMap(formattedRegistryValue).joined(separator: ", ")
            return formatted.isEmpty ? nil : formatted
        }
        return nil
    }
}
