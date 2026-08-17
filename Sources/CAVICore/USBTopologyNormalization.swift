import Foundation

public struct USBTopologyPresentation: Hashable, Sendable {
    public let technicalNodes: [ReconciledUSBTopologyNode]
    public let labels: [String]

    public init(technicalNodes: [ReconciledUSBTopologyNode], labels: [String]) {
        self.technicalNodes = technicalNodes
        self.labels = labels
    }

    public var breadcrumb: String { labels.joined(separator: " → ") }
}

public enum USBTopologyNormalizer {
    public static func presentationPath(for device: USBPhysicalDevice) -> USBTopologyPresentation {
        var labels: [String] = []
        for node in device.technicalTopology {
            switch node.kind {
            case .host, .controller, .rootHub:
                if labels.last != "Mac" { labels.append("Mac") }
            case .externalHub, .bridge, .physicalDevice:
                let label = node.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty, labels.last != label { labels.append(label) }
            }
        }
        return USBTopologyPresentation(technicalNodes: device.technicalTopology, labels: labels)
    }
}
