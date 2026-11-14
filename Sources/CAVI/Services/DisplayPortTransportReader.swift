import Foundation
import IOKit
import CAVICore

/// Reads the DisplayPort transports macOS exposes for every external display
/// (`IOPortTransportStateDisplayPort`). On Apple silicon this covers the HDMI port,
/// USB-C DisplayPort Alt Mode and Thunderbolt/USB4 tunnels alike.
enum DisplayPortTransportReader {
    nonisolated static func observations() -> [DisplayPortTransportObservation] {
        guard let matching = IOServiceMatching("IOPortTransportStateDisplayPort") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [DisplayPortTransportObservation] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let current = service
            defer { IOObjectRelease(current) }
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(current, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                result.append(observation(from: dict))
            }
            service = IOIteratorNext(iterator)
        }
        return result
    }

    /// Maps the registry dictionary; split out so it can be exercised without hardware.
    nonisolated static func observation(from dict: [String: Any]) -> DisplayPortTransportObservation {
        let metadata = dict["Metadata"] as? [String: Any]
        let hpdHigh: Bool = {
            if let description = dict["HPD_StateDescription"] as? String {
                return description.caseInsensitiveCompare("High") == .orderedSame
            }
            return int(dict["HPD_State"]) == 2
        }()
        let laneRate = (dict["NominalSignalingFrequenciesHz"] as? [Any])?.compactMap(uint64).max()
        return DisplayPortTransportObservation(
            portTypeDescription: dict["ParentPortTypeDescription"] as? String
                ?? dict["ParentBuiltInPortTypeDescription"] as? String,
            portNumber: int(dict["ParentPortNumber"]),
            isActive: bool(dict["Active"]),
            isHotPlugHigh: hpdHigh,
            isTunneled: bool(dict["Tunneled"]),
            laneRateHz: laneRate,
            linkRateDescription: dict["LinkRateDescription"] as? String,
            laneCount: int(dict["LaneCount"]),
            maxLaneCount: int(dict["MaxLaneCount"]),
            downstreamPortTypeDescription: metadata?["DFP Type Description"] as? String,
            productName: dict["ProductName"] as? String ?? metadata?["ProductName"] as? String,
            productID: int(dict["ProductID"]) ?? int(metadata?["ProductID"]),
            serialNumber: int(dict["SerialNumber"]) ?? int(metadata?["SerialNumber"]),
            manufacturerCode: dict["ManufacturerName"] as? String ?? metadata?["ManufacturerName"] as? String
        )
    }

    private nonisolated static func bool(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    private nonisolated static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }

    private nonisolated static func uint64(_ value: Any) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        return value as? UInt64
    }
}
