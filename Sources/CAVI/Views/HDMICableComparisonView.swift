import SwiftUI
import CAVICore

struct HDMICableComparisonView: View {
    @Environment(HDMICableHistoryStore.self) private var historyStore
    @Environment(LanguageManager.self) private var lm
    
    @State private var cableAId: UUID?
    @State private var cableBId: UUID?
    
    var body: some View {
        VStack(spacing: 24) {
            Text(lm.t("Cable Comparison", "Confronto Cavi"))
                .font(.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(alignment: .top, spacing: 24) {
                cableSelectorColumn(title: "Cable A", selection: $cableAId)
                cableSelectorColumn(title: "Cable B", selection: $cableBId)
            }
            
            if let a = cableAId, let b = cableBId,
               let profileA = historyStore.cables.first(where: { $0.id == a }),
               let profileB = historyStore.cables.first(where: { $0.id == b }) {
                comparisonTable(profileA: profileA, profileB: profileB)
            } else {
                Text(lm.t("Select two cables to compare.", "Seleziona due cavi per confrontarli."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    @ViewBuilder
    private func cableSelectorColumn(title: String, selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading) {
            Picker(title, selection: selection) {
                Text(lm.t("None", "Nessuno")).tag(UUID?.none)
                ForEach(historyStore.cables) { profile in
                    Text(profile.name).tag(Optional(profile.id))
                }
            }
            .pickerStyle(.menu)
            
            if let id = selection.wrappedValue, let profile = historyStore.cables.first(where: { $0.id == id }) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(lm.t("Name", "Nome"), value: profile.name)
                        LabeledContent(lm.t("Certification", "Certificazione"), value: profile.declaredCertification ?? "-")
                        LabeledContent(lm.t("Length", "Lunghezza"), value: profile.length ?? "-")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func comparisonTable(profileA: HDMICableProfile, profileB: HDMICableProfile) -> some View {
        GroupBox(lm.t("Results", "Risultati")) {
            let recordsA = profileA.testHistory
            let recordsB = profileB.testHistory
            
            let maxModeA = recordsA.max(by: { $0.maximumBandwidthGbps < $1.maximumBandwidthGbps })?.maximumVerifiedMode ?? "-"
            let maxModeB = recordsB.max(by: { $0.maximumBandwidthGbps < $1.maximumBandwidthGbps })?.maximumVerifiedMode ?? "-"
            
            let maxBandwidthA = recordsA.max(by: { $0.maximumBandwidthGbps < $1.maximumBandwidthGbps })?.maximumBandwidthGbps
            let maxBandwidthB = recordsB.max(by: { $0.maximumBandwidthGbps < $1.maximumBandwidthGbps })?.maximumBandwidthGbps
            
            let avgScoreA = recordsA.isEmpty ? "-" : "\(recordsA.map(\.stabilityScore).reduce(0, +) / recordsA.count)"
            let avgScoreB = recordsB.isEmpty ? "-" : "\(recordsB.map(\.stabilityScore).reduce(0, +) / recordsB.count)"
            
            let disconnectsA = recordsA.map(\.disconnects).reduce(0, +)
            let disconnectsB = recordsB.map(\.disconnects).reduce(0, +)
            
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    Text(lm.t("Metric", "Metrica")).font(.headline)
                    Text(profileA.name).font(.headline)
                    Text(profileB.name).font(.headline)
                }
                Divider()
                GridRow {
                    Text(lm.t("Max Verified Mode", "Modalità Max Verificata"))
                    Text(maxModeA)
                    Text(maxModeB)
                }
                Divider()
                GridRow {
                    Text(lm.t("Max Bandwidth", "Banda Max"))
                    Text(maxBandwidthA != nil ? String(format: "%.1f Gbps", maxBandwidthA!) : "-")
                    Text(maxBandwidthB != nil ? String(format: "%.1f Gbps", maxBandwidthB!) : "-")
                }
                Divider()
                GridRow {
                    Text(lm.t("Stability Score", "Punteggio Stabilità"))
                    Text(avgScoreA)
                    Text(avgScoreB)
                }
                Divider()
                GridRow {
                    Text(lm.t("Disconnects", "Disconnessioni"))
                    Text("\(disconnectsA)")
                    Text("\(disconnectsB)")
                }
            }
            .padding()
        }
    }
}
