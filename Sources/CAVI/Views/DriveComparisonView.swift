import SwiftUI
import CAVICore

struct DriveComparisonView: View {
    @Environment(TestHistoryStore.self) private var historyStore
    @Environment(LanguageManager.self) private var languageManager
    
    @State private var selectedEntries: Set<TestHistoryStore.DeviceHistoryEntry.ID> = []
    
    var body: some View {
        VStack(spacing: 0) {
            if historyStore.deviceHistory.isEmpty {
                ContentUnavailableView(
                    languageManager.t("No Device History", "Nessuna cronologia dispositivi"),
                    systemImage: "externaldrive.badge.xmark",
                    description: Text(languageManager.t("Run a benchmark to save device history.", "Esegui un benchmark per salvare la cronologia."))
                )
            } else {
                HStack(spacing: 0) {
                    // Sidebar: Selection list
                    VStack {
                        Text(languageManager.t("Select up to 3 drives", "Seleziona fino a 3 unità"))
                            .font(.headline)
                            .padding()
                        
                        List(historyStore.deviceHistory, selection: $selectedEntries) { entry in
                            VStack(alignment: .leading) {
                                Text(entry.deviceName).font(.headline)
                                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .listStyle(.sidebar)
                        .onChange(of: selectedEntries) { old, new in
                            if new.count > 3 {
                                // Keep only the 3 most recently selected (or just drop the last addition, which is harder with sets, so just drop an arbitrary one not in old)
                                let added = new.subtracting(old)
                                if let toRemove = added.first {
                                    var modified = new
                                    modified.remove(toRemove)
                                    selectedEntries = modified
                                }
                            }
                        }
                    }
                    .frame(width: 250)
                    
                    Divider()
                    
                    // Main: Comparison Table
                    let selectedItems = historyStore.deviceHistory.filter { selectedEntries.contains($0.id) }.prefix(3)
                    if selectedItems.isEmpty {
                        ContentUnavailableView(
                            languageManager.t("No Selection", "Nessuna selezione"),
                            systemImage: "sidebar.left",
                            description: Text(languageManager.t("Select drives from the sidebar to compare them.", "Seleziona le unità dalla barra laterale per confrontarle."))
                        )
                    } else {
                        comparisonTable(for: Array(selectedItems))
                    }
                }
            }
        }
        .navigationTitle(languageManager.t("Drive Comparison", "Confronto Unità"))
    }
    
    @ViewBuilder
    private func comparisonTable(for items: [TestHistoryStore.DeviceHistoryEntry]) -> some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                // Labels column
                VStack(alignment: .trailing, spacing: 16) {
                    Text(languageManager.t("Device", "Dispositivo")).fontWeight(.bold)
                    Divider()
                    Text(languageManager.t("Date", "Data"))
                    Text(languageManager.t("Read Speed", "Velocità Lettura"))
                    Text(languageManager.t("Write Speed", "Velocità Scrittura"))
                    Text(languageManager.t("Health Score", "Punteggio Salute"))
                    Text(languageManager.t("Temperature", "Temperatura"))
                    Text(languageManager.t("Connection Speed", "Velocità Connessione"))
                }
                .frame(width: 150)
                
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(item.deviceName).fontWeight(.bold).lineLimit(1)
                        Divider()
                        Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                        
                        if let read = item.benchmarkReadMBps {
                            Text(String(format: "%.1f MB/s", read))
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                        
                        if let write = item.benchmarkWriteMBps {
                            Text(String(format: "%.1f MB/s", write))
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                        
                        if let score = item.healthScore {
                            Text("\(score)/100")
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                        
                        if let temp = item.temperatureCelsius {
                            Text(String(format: "%.1f °C", temp))
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                        
                        if let speed = item.negotiatedSpeedBps {
                            Text(formatSpeed(bps: speed))
                        } else {
                            Text("—").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 200)
                }
            }
            .padding()
        }
    }
    
    private func formatSpeed(bps: UInt64) -> String {
        if bps >= 1_000_000_000 {
            let gbps = Double(bps) / 1_000_000_000.0
            return gbps.truncatingRemainder(dividingBy: 1.0) == 0 ? String(format: "%.0f Gb/s", gbps) : String(format: "%.1f Gb/s", gbps)
        } else if bps >= 1_000_000 {
            let mbps = Double(bps) / 1_000_000.0
            return String(format: "%.0f Mb/s", mbps)
        } else {
            return "\(bps) bps"
        }
    }
}
