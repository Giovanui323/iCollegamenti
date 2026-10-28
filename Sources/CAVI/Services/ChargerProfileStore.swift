import Foundation
import Observation

/// Keeps stored data that cannot be decoded (for example from a newer app version). Without this, the next save
/// would replace it with the current state and the data would be lost.
enum StoredDataRecovery {
    static func preserveUnreadable(_ data: Data, key: String) {
        let backupKey = "\(key).unreadable"
        guard UserDefaults.standard.data(forKey: backupKey) == nil else { return }
        UserDefaults.standard.set(data, forKey: backupKey)
    }
}

struct CertifiedCharger: Codable, Identifiable, Hashable {
    let id: UUID
    let brand: String
    let label: String
    let certifiedWatts: Int
    let dateAdded: Date

    init(id: UUID = UUID(), brand: String, label: String, certifiedWatts: Int, dateAdded: Date = Date()) {
        self.id = id
        self.brand = brand
        self.label = label
        self.certifiedWatts = certifiedWatts
        self.dateAdded = dateAdded
    }

    var displayName: String { "\(brand) — \(label) (\(certifiedWatts) W)" }
}

@Observable
@MainActor
final class ChargerProfileStore {
    private static let storageKey = "certifiedChargers.v1"
    private(set) var chargers: [CertifiedCharger] = []
    var selectedChargerID: UUID?

    init() { load() }

    var selectedCharger: CertifiedCharger? {
        chargers.first { $0.id == selectedChargerID }
    }

    func add(brand: String, label: String, watts: Int) {
        let cleanBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBrand.isEmpty, !cleanLabel.isEmpty, watts > 0 else { return }
        let charger = CertifiedCharger(brand: cleanBrand, label: cleanLabel, certifiedWatts: watts)
        chargers.append(charger)
        selectedChargerID = charger.id
        save()
    }

    func remove(_ charger: CertifiedCharger) {
        chargers.removeAll { $0.id == charger.id }
        if selectedChargerID == charger.id { selectedChargerID = nil }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        guard let saved = try? JSONDecoder().decode([CertifiedCharger].self, from: data) else {
            StoredDataRecovery.preserveUnreadable(data, key: Self.storageKey)
            return
        }
        chargers = saved
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(chargers) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
