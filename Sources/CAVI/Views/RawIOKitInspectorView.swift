import SwiftUI
import CAVICore
import AppKit

struct RawIOKitInspectorView: View {
    let device: DriveDevice
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(languageManager.t("Raw IOKit Properties", "Proprietà IOKit grezze"))
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    Button(action: copyAll) {
                        Label(languageManager.t("Copy All", "Copia tutto"), systemImage: "doc.on.doc")
                    }
                }
                
                if let snapshot = device.connectionSnapshot, !snapshot.technicalProperties.isEmpty {
                    GroupBox(languageManager.t("Technical Properties", "Proprietà Tecniche")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(snapshot.technicalProperties) { prop in
                                HStack(alignment: .top) {
                                    Text(prop.key)
                                        .fontWeight(.semibold)
                                        .frame(width: 150, alignment: .leading)
                                    Text(prop.value)
                                        .font(.body.monospaced())
                                }
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                if let snapshot = device.connectionSnapshot, let nodes = snapshot.ioRegistryNodeNames, !nodes.isEmpty {
                    GroupBox(languageManager.t("IO Registry Nodes", "Nodi IO Registry")) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(nodes, id: \.self) { node in
                                Text(node)
                                    .font(.body.monospaced())
                                Divider()
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                if !device.usbTopology.isEmpty {
                    GroupBox(languageManager.t("Topology Nodes", "Nodi della Topologia")) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(device.usbTopology.enumerated()), id: \.offset) { index, node in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Node \(index): \(node.className)")
                                        .fontWeight(.bold)
                                    if let vendorName = node.vendorName {
                                        Text("Vendor Name: \(vendorName)")
                                    }
                                    if let productName = node.productName {
                                        Text("Product Name: \(productName)")
                                    }
                                    if let vendorID = node.vendorID {
                                        Text(String(format: "Vendor ID: 0x%04X", vendorID))
                                    }
                                    if let productID = node.productID {
                                        Text(String(format: "Product ID: 0x%04X", productID))
                                    }
                                    if let serialNumber = node.serialNumber {
                                        Text("Serial Number: \(serialNumber)")
                                    }
                                    if let linkSpeedBps = node.linkSpeedBps {
                                        Text("Link Speed: \(formatSpeed(bps: linkSpeedBps))")
                                    }
                                    if let locationID = node.locationID {
                                        Text(String(format: "Location ID: 0x%08X", locationID))
                                    }
                                    Text("Is Hub: \(node.isHub ? "Yes" : "No")")
                                }
                                .font(.body.monospaced())
                                if index < device.usbTopology.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(languageManager.t("IOKit Inspector", "Inspector IOKit"))
    }
    
    private func copyAll() {
        var text = "Raw IOKit Properties\n\n"
        if let snapshot = device.connectionSnapshot, !snapshot.technicalProperties.isEmpty {
            text += "Technical Properties:\n"
            for prop in snapshot.technicalProperties {
                text += "\(prop.key): \(prop.value)\n"
            }
            text += "\n"
        }
        if let snapshot = device.connectionSnapshot, let nodes = snapshot.ioRegistryNodeNames, !nodes.isEmpty {
            text += "IO Registry Nodes:\n"
            for node in nodes {
                text += "\(node)\n"
            }
            text += "\n"
        }
        if !device.usbTopology.isEmpty {
            text += "Topology Nodes:\n"
            for (index, node) in device.usbTopology.enumerated() {
                text += "Node \(index): \(node.className)\n"
                if let vendorName = node.vendorName { text += "Vendor Name: \(vendorName)\n" }
                if let productName = node.productName { text += "Product Name: \(productName)\n" }
                if let vendorID = node.vendorID { text += String(format: "Vendor ID: 0x%04X\n", vendorID) }
                if let productID = node.productID { text += String(format: "Product ID: 0x%04X\n", productID) }
                if let serialNumber = node.serialNumber { text += "Serial Number: \(serialNumber)\n" }
                if let linkSpeedBps = node.linkSpeedBps { text += "Link Speed: \(formatSpeed(bps: linkSpeedBps))\n" }
                if let locationID = node.locationID { text += String(format: "Location ID: 0x%08X\n", locationID) }
                text += "Is Hub: \(node.isHub ? "Yes" : "No")\n"
                text += "\n"
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func formatSpeed(bps: UInt64?) -> String {
        guard let bps = bps else { return "Unknown" }
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
