import SwiftUI
import CAVICore

struct HDMIChainVisualizerView: View {
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(HDMIDisplayAnalysisService.self) private var hdmiAnalysis
    @Environment(LanguageManager.self) private var lm

    var body: some View {
        VStack(spacing: 24) {
            if let display = hdmiService.selectedDisplay {
                let config = hdmiAnalysis.currentConfiguration(for: display.displayID)
                
                let diagnosis = HDMIChainAnalyzer.analyze(
                    macGPU: "Apple Silicon",
                    portType: "HDMI",
                    adapterInfo: nil,
                    testedCableBandwidth: nil,
                    displayMaxMode: "Unknown",
                    currentMode: "\(config?.width ?? 0)x\(config?.height ?? 0)"
                )
                
                chainView(diagnosis: diagnosis)
            } else {
                Text(lm.t("No display selected", "Nessun display selezionato"))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func chainView(diagnosis: HDMIChainDiagnosis) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if diagnosis.nodes.isEmpty {
                    Text(lm.t("No nodes available.", "Nessun nodo disponibile."))
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(Array(diagnosis.nodes.enumerated()), id: \.offset) { index, node in
                        nodeView(node: node, isBottleneck: diagnosis.bottleneckNodeId == node.id)
                        
                        if index < diagnosis.nodes.count - 1 {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 4, height: 40)
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func nodeView(node: HDMIChainNode, isBottleneck: Bool) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(isBottleneck ? Color.orange.opacity(0.2) : Color.blue.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                Image(systemName: iconForNode(node.type))
                    .font(.system(size: 24))
                    .foregroundStyle(isBottleneck ? .orange : .blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(node.name)
                        .font(.headline)
                    if isBottleneck {
                        Text(lm.t("⚠️ BOTTLENECK", "⚠️ COLLO DI BOTTIGLIA"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text(node.capabilityDescription ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isBottleneck ? Color.orange : Color.secondary.opacity(0.2), lineWidth: isBottleneck ? 2 : 1)
        )
    }
    
    private func iconForNode(_ type: HDMIChainNodeType) -> String {
        switch type {
        case .gpu: return "cpu"
        case .port: return "cable.connector"
        case .adapter: return "rectangle.connected.to.line.below"
        case .cable: return "cable.connector.horizontal"
        case .receiver: return "hifispeaker.and.homepod"
        case .display: return "display"
        }
    }
}
