import Foundation

public enum BandwidthAccounting {
    public static func budget(
        forUplinkID uplinkID: String,
        in graph: ReconciledUSBStorageGraph
    ) -> BandwidthBudget? {
        guard let uplink = graph.uplinks.first(where: { $0.id == uplinkID }) else { return nil }

        let branches = graph.physicalDevices.reduce(into: [String: (node: ReconciledUSBTopologyNode, devices: [USBPhysicalDevice])]()) { branches, device in
            guard let child = immediateChild(of: uplinkID, for: device) else { return }
            var branch = branches[child.id] ?? (node: child, devices: [])
            branch.devices.append(device)
            branches[child.id] = branch
        }

        let consumers = branches.values
            .map { branch in
                let requestedSpeed: UInt64?
                if branch.node.kind == .externalHub {
                    // A nested hub cannot propagate more potential demand than
                    // the negotiated capacity of its own upstream branch.
                    requestedSpeed = branch.node.negotiatedSpeedBps
                } else {
                    requestedSpeed = branch.devices.compactMap(\.negotiatedLinkSpeedBps).max()
                }
                let label = branch.node.kind == .externalHub
                    ? "\(branch.node.displayName) (\(branch.devices.count) devices)"
                    : branch.devices.first?.displayName ?? branch.node.displayName
                return BandwidthConsumer(
                    id: branch.node.id,
                    label: label,
                    requestedSpeedBps: requestedSpeed
                )
            }
            .sorted { $0.id < $1.id }

        return BandwidthBudgetCalculator.calculate(
            uplinkSpeedBps: uplink.negotiatedSpeedBps,
            consumers: consumers
        )
    }

    private static func immediateChild(
        of uplinkID: String,
        for device: USBPhysicalDevice
    ) -> ReconciledUSBTopologyNode? {
        guard let index = device.technicalTopology.firstIndex(where: { $0.id == uplinkID }) else {
            return nil
        }
        let childIndex = device.technicalTopology.index(after: index)
        guard childIndex < device.technicalTopology.endIndex else { return nil }
        return device.technicalTopology[childIndex]
    }
}
