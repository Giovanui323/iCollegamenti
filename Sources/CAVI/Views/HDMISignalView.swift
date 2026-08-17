import SwiftUI
import CAVICore

struct HDMISignalView: View {
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(HDMIDisplayAnalysisService.self) private var hdmiAnalysis
    @Environment(LanguageManager.self) private var lm

    var body: some View {
        VStack(spacing: 24) {
            if let display = hdmiService.selectedDisplay {
                let config = hdmiAnalysis.currentConfiguration(for: display.displayID)
                
                heroSection(config: config)
                bandwidthSection(config: config)
                fallbackSection(config: config)
            } else {
                Text(lm.t("No display selected", "Nessun display selezionato"))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 600)
    }
    
    @ViewBuilder
    private func heroSection(config: HDMISignalConfiguration?) -> some View {
        GroupBox {
            VStack(spacing: 12) {
                Text("\(config?.width ?? 0) × \(config?.height ?? 0)")
                    .font(.system(size: 36, weight: .bold))
                
                HStack(spacing: 8) {
                    Text("\(String(format: "%.0f", config?.refreshRate ?? 0)) Hz")
                    Text("·")
                    Text("\(config?.bitDepth ?? 8)-bit")
                    Text("·")
                    Text(config?.chroma.description ?? "RGB")
                }
                .font(.title2)
                
                HStack(spacing: 16) {
                    if config?.isHDRActive == true {
                        Label(lm.t("HDR Active", "HDR Attivo"), systemImage: "sun.max.fill")
                            .foregroundStyle(.orange)
                    }
                    if config?.isVRRActive == true {
                        Label(lm.t("VRR Active", "VRR Attivo"), systemImage: "arrow.up.and.down.text.horizontal")
                            .foregroundStyle(.green)
                    }
                }
                .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
    
    @ViewBuilder
    private func bandwidthSection(config: HDMISignalConfiguration?) -> some View {
        GroupBox(lm.t("Bandwidth", "Larghezza di Banda")) {
            VStack(alignment: .leading, spacing: 16) {
                let required = config?.bandwidthRequirement.effectiveBandwidthGbps ?? 0
                let available = 48.0
                let headroomPct = available > 0 ? max(0, (available - required) / available) : 0
                
                LabeledContent(lm.t("Required", "Richiesta"), value: String(format: "%.1f Gbps", required))
                LabeledContent(lm.t("Available", "Disponibile"), value: String(format: "%.1f Gbps", available))
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(lm.t("Headroom", "Margine"))
                        Spacer()
                        Text(String(format: "%.0f%%", headroomPct * 100))
                    }
                    
                    ProgressView(value: headroomPct, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(headroomPct > 0.2 ? .green : (headroomPct > 0.05 ? .orange : .red))
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    @ViewBuilder
    private func fallbackSection(config: HDMISignalConfiguration?) -> some View {
        GroupBox {
            if hdmiAnalysis.fallbackDetection?.isFallback == true {
                SemanticStatus(
                    lm.t("Signal fallback detected", "Rilevato degrado del segnale"),
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .warning
                )
            } else {
                SemanticStatus(
                    lm.t("No signal fallback detected", "Nessun degrado del segnale"),
                    systemImage: "checkmark.circle.fill",
                    tone: .success
                )
            }
        }
    }
}
