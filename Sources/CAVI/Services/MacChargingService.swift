import Foundation
import IOKit.ps
import Observation
import CAVICore

struct MacChargingSnapshot: Sendable {
    let modelIdentifier: String
    let isOnExternalPower: Bool
    let adapterWatts: Int?
    let batteryWatts: Double?
    let batteryVoltageVolts: Double?
    let batteryCurrentAmps: Double?
    let batteryState: String
    let batteryPercent: Int?

    static let unavailable = MacChargingSnapshot(
        modelIdentifier: "Questo Mac",
        isOnExternalPower: false,
        adapterWatts: nil,
        batteryWatts: nil,
        batteryVoltageVolts: nil,
        batteryCurrentAmps: nil,
        batteryState: "Alimentazione non rilevata",
        batteryPercent: nil
    )

    var observedWatts: Double? { batteryWatts ?? adapterWatts.map(Double.init) }

    var assessment: String {
        guard isOnExternalPower else { return "Non collegato all'alimentazione" }
        guard let watts = observedWatts else { return "Alimentatore collegato" }
        switch watts {
        case ..<18: return "Ricarica lenta"
        case ..<45: return "Ricarica standard"
        case ..<70: return "Ricarica rapida"
        default: return "Alta potenza"
        }
    }

    var detail: String {
        if let batteryWatts {
            return "Potenza stimata lato batteria: \(String(format: "%.1f", batteryWatts)) W. Può essere inferiore alla potenza dell'alimentatore per consumi del Mac e gestione termica."
        }
        if let adapterWatts {
            return "Alimentatore da \(adapterWatts) W rilevato. macOS non ha esposto la potenza istantanea lato batteria."
        }
        return "Per una misura precisa del cavo servono caricatore, Mac e un misuratore USB-C PD inline."
    }
}

@Observable
@MainActor
final class MacChargingService {
    private static let historyStorageKey = "chargingHistory.v1"
    private(set) var snapshot = MacChargingSnapshot.unavailable
    private(set) var recentSamples: [ChargingSample] = []
    private var refreshTimer: Timer?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.historyStorageKey),
           let stored = try? JSONDecoder().decode([ChargingSample].self, from: data) {
            recentSamples = ChargingHistory.trim(stored, limit: 60)
        }
    }

    func startMonitoring() {
        guard refreshTimer == nil else { return }
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        let model = Self.hardwareModelIdentifier()
        let sourceType = IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String?
        let isOnExternalPower = sourceType == kIOPSACPowerValue
        let adapterWatts = Self.adapterWatts()
        let battery = Self.batteryMeasurement()
        snapshot = MacChargingSnapshot(
            modelIdentifier: model,
            isOnExternalPower: isOnExternalPower,
            adapterWatts: adapterWatts,
            batteryWatts: battery.watts,
            batteryVoltageVolts: battery.voltageVolts,
            batteryCurrentAmps: battery.currentAmps,
            batteryState: battery.state,
            batteryPercent: battery.percent
        )
        if let watts = snapshot.observedWatts {
            recentSamples = ChargingHistory.trim(recentSamples + [ChargingSample(watts: watts)], limit: 60)
            if let data = try? JSONEncoder().encode(recentSamples) {
                UserDefaults.standard.set(data, forKey: Self.historyStorageKey)
            }
        }
    }

    private static func adapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return nil }
        return details["Watts"] as? Int
    }

    private static func batteryMeasurement() -> (watts: Double?, voltageVolts: Double?, currentAmps: Double?, state: String, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return (nil, nil, nil, "Batteria non disponibile", nil) }
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source).takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String ?? "Stato batteria non disponibile"
            let current = description["Amperage"] as? Int
            let voltage = description["Voltage"] as? Int
            let watts = (current != nil && voltage != nil) ? abs(Double(current!) * Double(voltage!)) / 1_000_000.0 : nil
            let voltageVolts = voltage.map { Double($0) / 1_000.0 }
            let currentAmps = current.map { Double($0) / 1_000.0 }
            return (watts, voltageVolts, currentAmps, state, description[kIOPSCurrentCapacityKey] as? Int)
        }
        return (nil, nil, nil, "Questo Mac non espone una batteria", nil)
    }

    private static func hardwareModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &value, &size, nil, 0)
        let identifier = String(decoding: value.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        return identifier.isEmpty ? "Questo Mac" : identifier
    }
}
