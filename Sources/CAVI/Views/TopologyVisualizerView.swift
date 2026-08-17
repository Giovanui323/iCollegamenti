import SwiftUI
import CAVICore

struct TopologyVisualizerView: View {
    var nodes: [USBTopologyNode]
    var hubBudgets: [ObservedHubBudget] = []
    @Environment(LanguageManager.self) private var languageManager
    
    private var displayNodes: [USBTopologyNode] {
        // Show the controller, real hubs, and the endpoint — never internal driver layers.
        nodes.filter { node in
            node.className == "IOUSBHostDevice" || node.className.contains("XHCI")
        }.reversed().map { $0 }  // Reversed: Mac controller at top, device at bottom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displayNodes.isEmpty {
                Text(languageManager.t("No topology information available.", "Nessuna informazione sulla topologia disponibile."))
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(Array(displayNodes.enumerated()), id: \.offset) { index, node in
                    TopologyNodeView(node: node, isController: index == 0, isDevice: index == displayNodes.count - 1)

                    if let budget = hubBudget(for: node) {
                        TopologyBandwidthBudgetView(hubName: budget.hubName, budget: budget.budget)
                            .padding(.leading, 40)
                    }
                    
                    if index < displayNodes.count - 1 {
                        TopologyArrowView(speedBps: displayNodes[index + 1].linkSpeedBps)
                    }
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hubBudget(for node: USBTopologyNode) -> ObservedHubBudget? {
        guard let locationID = node.locationID else { return nil }
        return hubBudgets.first { $0.locationID == locationID }
    }
}

struct TopologyNodeView: View {
    var node: USBTopologyNode
    var isController: Bool
    var isDevice: Bool
    @Environment(LanguageManager.self) private var languageManager
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.headline)
                
                if let name = node.productName, !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let speed = node.linkSpeedBps {
                    Text(LinkSpeedService.formatSpeed(speed))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var iconName: String {
        if isController { return "desktopcomputer" }
        if node.isHub { return "cable.connector.horizontal" }
        if isDevice { return "externaldrive.fill" }
        return "cable.connector"
    }
    
    private var titleText: String {
        if isController { return "Mac" }
        if node.isHub { return node.productName ?? languageManager.t("USB Hub", "Hub USB") }
        return node.displayName
    }
}

private struct TopologyBandwidthBudgetView: View {
    let hubName: String
    let budget: BandwidthBudget
    @Environment(LanguageManager.self) private var languageManager

    private var tone: SemanticStatusTone {
        guard let saturation = budget.saturationPercent else { return .neutral }
        return saturation > 100 ? .warning : .neutral
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.t("Potential budget — \(hubName)", "Budget potenziale — \(hubName)"))
                .font(.subheadline.weight(.semibold))

            if let uplink = budget.uplinkSpeedBps {
                LabeledContent(
                    languageManager.t("Observed uplink", "Uplink osservato"),
                    value: LinkSpeedService.formatSpeed(uplink)
                )
            }
            if let demand = budget.potentialDemandBps {
                LabeledContent(
                    languageManager.t("Potential negotiated demand", "Domanda negoziata potenziale"),
                    value: LinkSpeedService.formatSpeed(demand)
                )
            }
            if let saturation = budget.saturationPercent {
                SemanticStatus(
                    saturation > 100
                        ? languageManager.t("Potential oversubscription: \(saturation)%", "Possibile sovra-allocazione: \(saturation)%")
                        : languageManager.t("Potential allocation: \(saturation)%", "Allocazione potenziale: \(saturation)%"),
                    systemImage: saturation > 100 ? "exclamationmark.triangle.fill" : "arrow.left.arrow.right",
                    tone: tone
                )
            }

            if budget.hasIncompleteDemand {
                Text(languageManager.t(
                    "Some connected devices did not expose a negotiated link speed.",
                    "Alcuni dispositivi collegati non hanno esposto una velocità di link negoziata."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(languageManager.t(
                "This compares observed negotiated links; it is not a measurement of live traffic or usable throughput.",
                "Confronta link negoziati osservati: non misura traffico reale né throughput disponibile."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }
}

struct TopologyArrowView: View {
    var speedBps: UInt64?
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.down")
                .foregroundColor(.secondary)
            
            if let speed = speedBps, speed > 0 {
                Text(LinkSpeedService.formatSpeed(speed))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
