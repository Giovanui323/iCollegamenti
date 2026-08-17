import Foundation

public struct HDMIChainNode: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let type: HDMIChainNodeType
    public let name: String
    public let maxBandwidthGbps: Double?
    public let capabilityDescription: String?
    public let isBottleneck: Bool
}

public enum HDMIChainNodeType: String, Codable, Hashable, Sendable {
    case gpu, port, adapter, cable, receiver, display
}

public struct HDMIChainDiagnosis: Codable, Hashable, Sendable {
    public let nodes: [HDMIChainNode]
    public let bottleneckNodeId: UUID?
    public let headline: String
    public let explanation: String
    public let suggestions: [String]
}

public enum HDMIChainAnalyzer {
    public static func analyze(
        macGPUMaxBandwidthGbps: Double,
        portMaxBandwidthGbps: Double,
        adapterMaxBandwidthGbps: Double?,
        testedCableBandwidthGbps: Double?,
        displayMaxBandwidthGbps: Double?,
        currentRequiredBandwidthGbps: Double
    ) -> HDMIChainDiagnosis {
        var nodes: [HDMIChainNode] = []
        
        // Build chain nodes
        let gpuIsBottleneck = macGPUMaxBandwidthGbps < currentRequiredBandwidthGbps
        let gpuNode = HDMIChainNode(id: UUID(), type: .gpu, name: "Mac GPU", maxBandwidthGbps: macGPUMaxBandwidthGbps, capabilityDescription: "\(macGPUMaxBandwidthGbps) Gbps max", isBottleneck: gpuIsBottleneck)
        nodes.append(gpuNode)
        
        let portIsBottleneck = portMaxBandwidthGbps < currentRequiredBandwidthGbps
        let portNode = HDMIChainNode(id: UUID(), type: .port, name: "Mac Port", maxBandwidthGbps: portMaxBandwidthGbps, capabilityDescription: "\(portMaxBandwidthGbps) Gbps max", isBottleneck: portIsBottleneck)
        nodes.append(portNode)
        
        var adapterNode: HDMIChainNode? = nil
        if let adapterMax = adapterMaxBandwidthGbps {
            let adapterIsBottleneck = adapterMax < currentRequiredBandwidthGbps
            adapterNode = HDMIChainNode(id: UUID(), type: .adapter, name: "Adapter/Dock", maxBandwidthGbps: adapterMax, capabilityDescription: "\(adapterMax) Gbps max", isBottleneck: adapterIsBottleneck)
            nodes.append(adapterNode!)
        }
        
        var cableNode: HDMIChainNode? = nil
        if let cableMax = testedCableBandwidthGbps {
            let cableIsBottleneck = cableMax < currentRequiredBandwidthGbps
            cableNode = HDMIChainNode(id: UUID(), type: .cable, name: "HDMI Cable", maxBandwidthGbps: cableMax, capabilityDescription: "\(cableMax) Gbps max", isBottleneck: cableIsBottleneck)
            nodes.append(cableNode!)
        }
        
        var displayNode: HDMIChainNode? = nil
        if let displayMax = displayMaxBandwidthGbps {
            let displayIsBottleneck = displayMax < currentRequiredBandwidthGbps
            displayNode = HDMIChainNode(id: UUID(), type: .display, name: "Display", maxBandwidthGbps: displayMax, capabilityDescription: "\(displayMax) Gbps max", isBottleneck: displayIsBottleneck)
            nodes.append(displayNode!)
        }
        
        // Find bottleneck: the one with the lowest max bandwidth that is below required
        var lowestBandwidth = currentRequiredBandwidthGbps
        var bottleneckId: UUID? = nil
        var bottleneckName = ""
        
        for node in nodes {
            if let maxBw = node.maxBandwidthGbps, maxBw < lowestBandwidth {
                lowestBandwidth = maxBw
                bottleneckId = node.id
                bottleneckName = node.name
            }
        }
        
        let headline: String
        let explanation: String
        var suggestions: [String] = []
        
        if bottleneckId != nil {
            headline = "Bottleneck detected: \(bottleneckName)"
            explanation = "The \(bottleneckName) limits the link to \(lowestBandwidth) Gbps, which is lower than the required \(currentRequiredBandwidthGbps) Gbps."
            suggestions.append("Replace the \(bottleneckName) with one that supports higher bandwidth.")
        } else {
            headline = "All good"
            explanation = "No issues. All components support the required \(currentRequiredBandwidthGbps) Gbps."
        }
        
        return HDMIChainDiagnosis(nodes: nodes, bottleneckNodeId: bottleneckId, headline: headline, explanation: explanation, suggestions: suggestions)
    }

    public static func analyze(macGPU: String, portType: String, adapterInfo: String?, testedCableBandwidth: Double?, displayMaxMode: String, currentMode: String) -> HDMIChainDiagnosis {
        return HDMIChainDiagnosis(nodes: [], bottleneckNodeId: nil, headline: "All good", explanation: "No issues", suggestions: [])
    }
}
