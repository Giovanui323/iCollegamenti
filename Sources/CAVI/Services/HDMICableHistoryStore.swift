import Foundation
import CAVICore

public struct HDMICableProfile: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var manufacturer: String?
    public var length: String?
    public var declaredCertification: String?
    public var location: String?
    public var notes: String?
    public var testHistory: [HDMICableTestRecord]
    public let created: Date
    
    public init(id: UUID = UUID(), name: String, manufacturer: String? = nil, length: String? = nil, declaredCertification: String? = nil, location: String? = nil, notes: String? = nil, testHistory: [HDMICableTestRecord] = [], created: Date = Date()) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.length = length
        self.declaredCertification = declaredCertification
        self.location = location
        self.notes = notes
        self.testHistory = testHistory
        self.created = created
    }
}

public struct HDMICableTestRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let displayName: String
    public let maximumVerifiedMode: String
    public let maximumBandwidthGbps: Double
    public let stressTestDuration: Int?
    public let disconnects: Int
    public let renegotiations: Int
    public let stabilityScore: Int
    public let overallScore: Int
    
    public init(id: UUID = UUID(), timestamp: Date = Date(), displayName: String, maximumVerifiedMode: String, maximumBandwidthGbps: Double, stressTestDuration: Int? = nil, disconnects: Int, renegotiations: Int, stabilityScore: Int, overallScore: Int) {
        self.id = id
        self.timestamp = timestamp
        self.displayName = displayName
        self.maximumVerifiedMode = maximumVerifiedMode
        self.maximumBandwidthGbps = maximumBandwidthGbps
        self.stressTestDuration = stressTestDuration
        self.disconnects = disconnects
        self.renegotiations = renegotiations
        self.stabilityScore = stabilityScore
        self.overallScore = overallScore
    }
}

@Observable
@MainActor
public final class HDMICableHistoryStore {
    public var cables: [HDMICableProfile] = []
    
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("iCollegamenti", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hdmi-cables.json")
    }()

    public init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HDMICableProfile].self, from: data)
        else { return }
        cables = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cables) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func addCable(_ cable: HDMICableProfile) {
        cables.append(cable)
        save()
    }

    public func addTestRecord(cableID: UUID, record: HDMICableTestRecord) {
        guard let index = cables.firstIndex(where: { $0.id == cableID }) else { return }
        cables[index].testHistory.append(record)
        save()
    }

    public func deleteCable(id: UUID) {
        cables.removeAll { $0.id == id }
        save()
    }
}
