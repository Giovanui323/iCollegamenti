import SwiftUI
import CAVICore

struct InspectorDetailsView: View {
    let device: DriveDevice?
    let display: HDMIDisplayDevice?
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        Group {
            if let display {
                DisplayInspectorDetails(display: display)
            } else if let device {
                DeviceInspectorDetails(device: device)
            } else {
                ContentUnavailableView(
                    languageManager.t("No Item Selected", "Nessun dettaglio selezionato"),
                    systemImage: "sidebar.right",
                    description: Text(languageManager.t("Select a USB device or external display to view its technical details.", "Seleziona un dispositivo USB o un display esterno per visualizzarne i dettagli tecnici."))
                )
                .padding()
            }
        }
        .navigationTitle(languageManager.t("Inspector", "Inspector"))
    }
}

private struct DeviceInspectorDetails: View {
    let device: DriveDevice
    @Environment(LanguageManager.self) private var languageManager
    @Environment(DriveHealthService.self) private var driveHealthService

    var body: some View {
        Form {
            Section(languageManager.t("Hardware Identifiers", "Identificativi hardware")) {
                LabeledContent(languageManager.t("Serial", "Seriale"), value: device.serialNumber ?? languageManager.t("Not available", "Non disponibile"))
                LabeledContent("Vendor ID", value: hexadecimal(device.vendorID, width: 4, lm: languageManager))
                LabeledContent("Product ID", value: hexadecimal(device.productID, width: 4, lm: languageManager))
                LabeledContent("Location ID", value: hexadecimal(device.locationID, width: 8, lm: languageManager))
            }

            Section(languageManager.t("Connection", "Connessione")) {
                LabeledContent(languageManager.t("Protocol", "Protocollo"), value: device.connectionSnapshot?.protocolName ?? device.protocol_ ?? languageManager.t("Not available", "Non disponibile"))
                LabeledContent(
                    languageManager.t("Negotiated link", "Link negoziato"),
                    value: device.connectionSnapshot?.negotiatedLinkSpeedBps.map(LinkSpeedService.formatSpeed) ?? device.negotiatedSpeedBps.map(LinkSpeedService.formatSpeed) ?? languageManager.t("Not available", "Non disponibile")
                )
                LabeledContent(languageManager.t("Connection Origin", "Origine"), value: device.connectionDescription(using: languageManager))
                if device.storageConnectionKind.supportsUSBTopology {
                    LabeledContent(
                        languageManager.t("Topology", "Topologia"),
                        value: USBTopologyService.topologyDescription(for: device).isEmpty
                            ? languageManager.t("Not available", "Non disponibile")
                            : USBTopologyService.topologyDescription(for: device)
                    )
                } else {
                    LabeledContent(languageManager.t("Topology", "Topologia"), value: languageManager.t("No USB path to diagnose", "Nessun percorso USB da diagnosticare"))
                }
            }

            if let snapshot = device.connectionSnapshot {
                Section(languageManager.t("Observed Connection Details", "Dettagli del collegamento osservati")) {
                    if let fileSystem = snapshot.fileSystem {
                        LabeledContent(languageManager.t("File system", "File system"), value: fileSystem)
                    }
                    if let blockSize = snapshot.blockSizeBytes {
                        LabeledContent(
                            languageManager.t("Block size", "Dimensione blocco"),
                            value: ByteCountFormatter.string(fromByteCount: Int64(blockSize), countStyle: .file)
                        )
                    }
                    if let bridge = snapshot.bridge {
                        LabeledContent(languageManager.t("Bridge family", "Famiglia bridge"), value: bridge.family)
                        Text(languageManager.t(
                            "Bridge family is an exact USB identifier catalog match, not a cable or firmware certification.",
                            "La famiglia bridge è un abbinamento esatto del catalogo di identificativi USB, non una certificazione del cavo o del firmware."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let bridge = BridgeCatalog.match(vendorID: device.vendorID, productID: device.productID) {
                        Section("Bridge Controller") {
                            LabeledContent("Controller", value: bridge.family)
                            LabeledContent("Vendor ID", value: hexadecimal(bridge.vendorID, width: 4, lm: languageManager))
                            LabeledContent("Product ID", value: hexadecimal(bridge.productID, width: 4, lm: languageManager))
                        }
                    }
                    if !snapshot.technicalProperties.isEmpty {
                        DisclosureGroup(languageManager.t("Raw USB Properties", "Proprietà USB rilevate")) {
                            ForEach(snapshot.technicalProperties) { property in
                                LabeledContent(property.key, value: property.value)
                            }
                        }
                    }
                    if let nodeNames = snapshot.ioRegistryNodeNames, !nodeNames.isEmpty {
                        DisclosureGroup(languageManager.t("I/O Registry Nodes", "Nodi I/O Registry")) {
                            ForEach(Array(nodeNames.enumerated()), id: \.offset) { _, nodeName in
                                Text(nodeName)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            if device.isStorageDevice {
                Section(languageManager.t("Volume", "Volume")) {
                    LabeledContent("File system", value: device.fileSystem ?? languageManager.t("Not available", "Non disponibile"))
                    LabeledContent(languageManager.t("Capacity", "Capacità"), value: device.capacityFormatted)
                    LabeledContent(languageManager.t("Free Space", "Spazio libero"), value: device.freeSpaceFormatted)
                    LabeledContent(languageManager.t("Mount Status", "Montaggio"), value: device.isMountedVolume ? languageManager.t("Mounted", "Montato") : languageManager.t("Unmounted", "Non montato"))
                }
                
                Section(languageManager.t("Drive Health", "Salute unità")) {
                    if let snapshot = driveHealthService.snapshot(for: device) {
                        LabeledContent(
                            languageManager.t("SMART Status", "Stato SMART"),
                            value: {
                                switch snapshot.smartStatus {
                                case .verified: return languageManager.t("Verified (Healthy)", "Verificato (Funzionante)")
                                case .failing: return languageManager.t("Failing (Critical)", "In errore (Critico)")
                                case .unavailable: return languageManager.t("Not exposed via USB", "Non esposto via USB")
                                }
                            }()
                        )
                        if let temp = snapshot.temperatureCelsius {
                            LabeledContent(languageManager.t("Temperature", "Temperatura"), value: String(format: "%.1f °C", temp))
                        }
                        if let life = snapshot.remainingLifePercent {
                            LabeledContent(languageManager.t("Remaining Life", "Vita residua"), value: "\(life)%")
                        }
                        if let poh = snapshot.powerOnHours {
                            LabeledContent(languageManager.t("Power-On Hours", "Ore di accensione"), value: "\(poh)")
                        }
                        if let cycles = snapshot.powerCycleCount {
                            LabeledContent(languageManager.t("Power Cycles", "Cicli di accensione"), value: "\(cycles)")
                        }
                        if let tbw = snapshot.totalBytesWritten {
                            LabeledContent(languageManager.t("Total Written", "Totale scritto"), value: ByteCountFormatter.string(fromByteCount: Int64(tbw), countStyle: .file))
                        }
                        if let errors = snapshot.mediaErrorCount, errors > 0 {
                            LabeledContent(languageManager.t("Media Errors", "Errori supporto"), value: "\(errors)")
                                .foregroundStyle(.red)
                        }
                        LabeledContent(
                            languageManager.t("Health Score", "Punteggio salute"),
                            value: snapshot.smartStatus == .unavailable
                                ? languageManager.t("Not assessable", "Non valutabile")
                                : "\(snapshot.assessment.score)/100"
                        )
                        if snapshot.smartStatus == .unavailable || (snapshot.temperatureCelsius == nil && snapshot.remainingLifePercent == nil) {
                            Text(languageManager.t(
                                "Standard USB flash drives and basic enclosures do not expose temperature, wear, or power-on metrics to macOS.",
                                "Le chiavette USB standard e alcuni enclosure non espongono a macOS dati su temperatura, usura o ore di utilizzo."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(languageManager.t("Health data unavailable", "Dati sulla salute non disponibili"))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text(languageManager.t(
                    "macOS does not expose a physical cable identity or certification. Some Apple Silicon USB-C controllers can expose PD/e-marker data for the current connection.",
                    "macOS non espone un’identità fisica o una certificazione del cavo. Alcuni controller USB-C Apple Silicon possono esporre dati PD/e-marker del collegamento corrente."
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 250, ideal: 300, max: 380)
        .task(id: device.bsdName) {
            await driveHealthService.refresh(device)
        }
    }
}

private struct DisplayInspectorDetails: View {
    let display: HDMIDisplayDevice
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        Form {
            Section(languageManager.t("Signal Details", "Dettagli segnale")) {
                LabeledContent(languageManager.t("Refresh Rate", "Frequenza"), value: "\(Int(display.refreshRateHz.rounded())) Hz")
                LabeledContent(languageManager.t("Depth", "Profondità"), value: "\(display.colorDepthBits) \(languageManager.t("bits/channel", "bit/canale"))")
                LabeledContent("HDR", value: display.isHDRSupported ? languageManager.t("Supported", "Supportato") : languageManager.t("Not detected", "Non rilevato"))
                LabeledContent(languageManager.t("Transport", "Trasporto"), value: display.connectionTransport)
            }

            Section {
                Text(languageManager.t(
                    "Display mode is observed from macOS; macOS does not expose raw physical cable certification.",
                    "La modalità video è osservata; macOS non espone il trasporto effettivo o la certificazione fisica del cavo."
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 250, ideal: 300, max: 380)
    }
}

private func hexadecimal(_ value: Int?, width: Int, lm: LanguageManager) -> String {
    guard let value else { return lm.t("Not available", "Non disponibile") }
    return String(format: "0x%0*X", width, value)
}
