import SwiftUI
import CAVICore

struct USBConnectionsView: View {
    @Environment(DeviceDiscoveryService.self) private var deviceDiscovery
    @Environment(USBCableEvidenceDiscoveryService.self) private var cableEvidence
    @Environment(USBVendorCatalog.self) private var vendorCatalog
    @Environment(LanguageManager.self) private var languageManager

    @State private var expandedIDs: Set<String> = []
    @State private var isMounting = false
    @State private var isEjecting = false
    @State private var mountErrorMessage: String?

    private var connections: [USBConnectionSnapshot] {
        USBConnectionDiscoveryService.snapshots(in: deviceDiscovery.reconciledGraph)
    }

    var body: some View {
        List {
            USBCableEvidenceSection()

            if let mountErrorMessage {
                Section {
                    Label(mountErrorMessage, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }

            ForEach(connections) { connection in
                let device = matchingDevice(for: connection)
                USBConnectionRow(
                    connection: connection,
                    matchingDevice: device,
                    vendorName: vendorName(for: connection),
                    productName: productName(for: connection),
                    isExpanded: expansionBinding(for: connection, matchingDevice: device),
                    isMounting: isMounting,
                    isEjecting: isEjecting,
                    mount: mountVolume,
                    eject: ejectVolume,
                    copyDetails: copyDetails
                )
            }
        }
        .listStyle(.inset)
        .overlay {
            if connections.isEmpty && !cableEvidence.snapshot.hasReadablePorts {
                ContentUnavailableView(
                    languageManager.t("No USB Peripherals", "Nessuna periferica USB"),
                    systemImage: "cable.connector",
                    description: Text(languageManager.t(
                        "Connect a device and refresh the list. USB-C controller data may not be exposed on this Mac.",
                        "Collega un dispositivo e aggiorna l’elenco. I dati del controller USB-C potrebbero non essere esposti su questo Mac."
                    ))
                )
            }
        }
    }

    private func matchingDevice(for connection: USBConnectionSnapshot) -> DriveDevice? {
        deviceDiscovery.devices.first { $0.physicalDeviceID == connection.id }
    }

    private func vendorName(for connection: USBConnectionSnapshot) -> String {
        vendorCatalog.name(for: connection.vendorID) ?? matchingDevice(for: connection)?.vendorName ?? languageManager.t("Uncataloged Manufacturer", "Produttore non catalogato")
    }

    private func productName(for connection: USBConnectionSnapshot) -> String {
        vendorCatalog.productName(for: connection.vendorID, productID: connection.productID) ?? matchingDevice(for: connection)?.productName ?? connection.displayName
    }

    private func expansionBinding(for connection: USBConnectionSnapshot, matchingDevice: DriveDevice?) -> Binding<Bool> {
        Binding(
            get: { expandedIDs.contains(connection.id) },
            set: { isExpanded in
                if isExpanded {
                    expandedIDs.insert(connection.id)
                    if let matchingDevice {
                        deviceDiscovery.selectedDevice = matchingDevice
                    }
                } else {
                    expandedIDs.remove(connection.id)
                }
            }
        )
    }

    private func mountVolume(_ bsdName: String) {
        isMounting = true
        mountErrorMessage = nil
        Task { @MainActor in
            defer { isMounting = false }
            guard let device = deviceDiscovery.devices.first(where: { $0.bsdName == bsdName }) else {
                mountErrorMessage = languageManager.t(
                    "The selected USB device is no longer available.",
                    "Il dispositivo USB selezionato non è più disponibile."
                )
                return
            }
            do {
                try await deviceDiscovery.mountDevice(device)
            } catch {
                mountErrorMessage = error.localizedDescription
            }
        }
    }

    private func ejectVolume(_ device: DriveDevice) {
        isEjecting = true
        Task { @MainActor in
            defer { isEjecting = false }
            try? await deviceDiscovery.ejectDevice(device)
        }
    }

    private func copyDetails(_ connection: USBConnectionSnapshot, _ vendorName: String, _ productName: String, _ matchingDevice: DriveDevice?) {
        let unavailable = languageManager.t("Not available", "Non disponibile")
        let header = languageManager.t("=== USB PERIPHERAL DETAILS (REDACTED) ===", "=== DETTAGLI PERIFERICA USB (REDATTI) ===")
        let text = """
        \(header)
        \(languageManager.t("Manufacturer (API)", "Produttore (API)")): \(vendorName)
        \(languageManager.t("Model (API)", "Modello (API)")): \(productName)
        \(languageManager.t("Device Name", "Nome Dispositivo")): \(connection.displayName)
        \(languageManager.t("Negotiated Link", "Link Negoziato")): \(connection.linkSpeedBps.map(formatConnectionSpeed) ?? unavailable)
        \(languageManager.t("Volume state", "Stato volume")): \(redactedVolumeState(for: connection, lm: languageManager))
        Vendor ID: \(hex(connection.vendorID, width: 4, lm: languageManager))
        Product ID: \(hex(connection.productID, width: 4, lm: languageManager))
        \(languageManager.t("USB Topology", "Topologia USB")): \(matchingDevice.map { USBTopologyService.topologyDescription(for: $0) } ?? unavailable)
        \(languageManager.t("Bridge family", "Famiglia bridge")): \(matchingDevice?.connectionSnapshot?.bridge?.family ?? unavailable)
        \(languageManager.t("File system", "File system")): \(matchingDevice?.connectionSnapshot?.fileSystem ?? unavailable)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct USBConnectionRow: View {
    let connection: USBConnectionSnapshot
    let matchingDevice: DriveDevice?
    let vendorName: String
    let productName: String
    @Binding var isExpanded: Bool
    let isMounting: Bool
    let isEjecting: Bool
    let mount: (String) -> Void
    let eject: (DriveDevice) -> Void
    let copyDetails: (USBConnectionSnapshot, String, String, DriveDevice?) -> Void
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                if let speed = connection.linkSpeedBps {
                    LabeledContent(languageManager.t("Negotiated Link", "Link negoziato"), value: formatConnectionSpeed(speed))
                    LabeledContent(languageManager.t("USB Standard", "Standard USB"), value: LinkSpeedRating.from(speedBps: speed).protocolDescription)
                } else {
                    LabeledContent(languageManager.t("Negotiated Link", "Link negoziato"), value: languageManager.t("Not available", "Non disponibile"))
                }

                if connection.linkSpeedBps == nil || matchingDevice?.connectionSnapshot == nil {
                    SemanticStatus(
                        languageManager.t("Some connection data is not exposed by macOS", "Alcuni dati del collegamento non sono esposti da macOS"),
                        systemImage: "questionmark.circle",
                        tone: .neutral
                    )
                }

                if connection.isStorageDevice {
                    LabeledContent(languageManager.t("Volume", "Volume"), value: volumeDescription(for: connection, lm: languageManager))
                    if let matchingDevice {
                        LabeledContent(languageManager.t("Capacity", "Capacità"), value: matchingDevice.capacityFormatted)
                    }
                } else {
                    Text(languageManager.t("No storage volume is associated with this peripheral.", "Nessun volume di archiviazione associato a questa periferica."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let snapshot = matchingDevice?.connectionSnapshot {
                    connectionSnapshotDetails(snapshot)
                }

                connectionActions
            }
            .padding(.vertical, 8)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: connection.isStorageDevice ? "externaldrive" : "cable.connector")
                VStack(alignment: .leading, spacing: 2) {
                    Text(productName)
                    Text(vendorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if connection.isStorageDevice {
                    statusLabel
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var connectionActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                storageAction
                copyDetailsButton
            }

            VStack(alignment: .leading, spacing: 8) {
                storageAction
                copyDetailsButton
            }
        }
    }

    @ViewBuilder
    private func connectionSnapshotDetails(_ snapshot: ConnectionSnapshot) -> some View {
        if let protocolName = snapshot.protocolName {
            LabeledContent(languageManager.t("Protocol", "Protocollo"), value: protocolName)
        }

        if let bridge = snapshot.bridge {
            LabeledContent(languageManager.t("Bridge family", "Famiglia bridge"), value: bridge.family)
            Text(languageManager.t(
                "Catalog match only: it does not certify the cable or the current bandwidth.",
                "Solo abbinamento di catalogo: non certifica il cavo né la banda attuale."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            LabeledContent(
                languageManager.t("Bridge family", "Famiglia bridge"),
                value: languageManager.t("Bridge not identified", "Bridge non identificato")
            )
        }

        if let blockSize = snapshot.blockSizeBytes {
            LabeledContent(
                languageManager.t("Block size", "Dimensione blocco"),
                value: ByteCountFormatter.string(fromByteCount: Int64(blockSize), countStyle: .file)
            )
        }

        if !snapshot.technicalProperties.isEmpty {
            DisclosureGroup(languageManager.t("Observed USB Properties", "Proprietà USB rilevate")) {
                ForEach(snapshot.technicalProperties) { property in
                    LabeledContent(property.key, value: property.value)
                }
            }
        }
    }

    @ViewBuilder
    private var storageAction: some View {
        if connection.isStorageDevice && !connection.isMounted, let bsdName = connection.bsdName {
            Button(
                isMounting
                    ? languageManager.t("Mounting…", "Montaggio…")
                    : languageManager.t("Mount Volume", "Monta volume"),
                systemImage: "externaldrive.badge.plus"
            ) {
                mount(bsdName)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isMounting)
        } else if connection.isMounted, let matchingDevice {
            Button(
                isEjecting
                    ? languageManager.t("Ejecting…", "Espulsione…")
                    : languageManager.t("Safely Eject", "Espelli in sicurezza"),
                systemImage: "eject.fill"
            ) {
                eject(matchingDevice)
            }
            .buttonStyle(.bordered)
            .disabled(isEjecting)
        }
    }

    private var copyDetailsButton: some View {
        Button(languageManager.t("Copy Details", "Copia dettagli"), systemImage: "doc.on.doc") {
            copyDetails(connection, vendorName, productName, matchingDevice)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if connection.isBenchmarkable {
            SemanticStatus(languageManager.t("Mounted", "Montato"), systemImage: "checkmark.circle.fill", tone: .success)
        } else {
            SemanticStatus(languageManager.t("Unmounted", "Non montato"), systemImage: "exclamationmark.triangle.fill", tone: .warning)
        }
    }
}

private func volumeDescription(for connection: USBConnectionSnapshot, lm: LanguageManager) -> String {
    if connection.isMounted {
        if let path = connection.mountPath, !path.isEmpty {
            return "\(connection.bsdName ?? lm.t("Mounted", "Montato")) — \(path)"
        }
        return connection.bsdName ?? lm.t("Mounted", "Montato")
    }
    return connection.isStorageDevice ? "\(connection.bsdName ?? lm.t("USB Drive", "Disco USB")) (\(lm.t("unmounted", "non montato")))" : lm.t("No storage volume", "Nessun volume di archiviazione")
}

private func redactedVolumeState(for connection: USBConnectionSnapshot, lm: LanguageManager) -> String {
    guard connection.isStorageDevice else {
        return lm.t("No storage volume", "Nessun volume di archiviazione")
    }
    return connection.isMounted ? lm.t("Mounted", "Montato") : lm.t("Unmounted", "Non montato")
}

private func formatConnectionSpeed(_ bps: UInt64) -> String {
    bps >= 1_000_000_000 ? String(format: "%.0f Gb/s", Double(bps) / 1_000_000_000) : "\(bps / 1_000_000) Mb/s"
}

private func hex(_ value: Int?, width: Int, lm: LanguageManager) -> String {
    guard let value else { return lm.t("Not available", "Non disponibile") }
    return String(format: "0x%0*X", width, value)
}
