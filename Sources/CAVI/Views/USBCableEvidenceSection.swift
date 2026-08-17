import SwiftUI
import CAVICore

/// A compact, per-port rendering of information the current Mac exposes from
/// its USB-C controllers. It deliberately distinguishes a missing value from a
/// negative conclusion about the cable.
struct USBCableEvidenceSection: View {
    @Environment(USBCableEvidenceDiscoveryService.self) private var evidenceDiscovery
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        Section {
            if evidenceDiscovery.snapshot.hasReadablePorts {
                ForEach(evidenceDiscovery.snapshot.ports) { port in
                    USBCableEvidencePortRow(port: port)
                }
            } else {
                SemanticStatus(
                    languageManager.t(
                        "This Mac did not expose readable USB-C port-controller data.",
                        "Questo Mac non ha esposto dati leggibili dei controller USB-C."
                    ),
                    systemImage: "questionmark.circle",
                    tone: .neutral
                )
            }
        } header: {
            NativeSectionHeader(
                languageManager.t("USB-C Electronic Data", "Dati elettronici USB-C"),
                detail: languageManager.t(
                    "Local I/O Registry — not a physical cable certification.",
                    "Registro I/O locale — non è una certificazione fisica del cavo."
                )
            )
        }
    }
}

private struct USBCableEvidencePortRow: View {
    let port: USBCableEvidencePort
    private let pdProperties: [PDProperty]

    @Environment(LanguageManager.self) private var languageManager

    init(port: USBCableEvidencePort) {
        self.port = port
        pdProperties = port.cableIdentityProperties
            .map { PDProperty(key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: portSymbol)
                    .foregroundStyle(portTone.foregroundStyle)
                    .accessibilityHidden(true)
                Text(port.portName)
                    .font(.headline)
                Spacer(minLength: 0)
                stateStatus
            }

            if !port.transports.isEmpty {
                LabeledContent(
                    languageManager.t("Active transports", "Trasporti attivi"),
                    value: port.transports.joined(separator: ", ")
                )
                .font(.subheadline)
            }

            if let activeCable = port.activeCable {
                LabeledContent(
                    languageManager.t("Active cable", "Cavo attivo"),
                    value: activeCable
                        ? languageManager.t("Reported by controller", "Segnalato dal controller")
                        : languageManager.t("Not reported by controller", "Non segnalato dal controller")
                )
                .font(.subheadline)
            }

            observedAttention

            if !pdProperties.isEmpty {
                DisclosureGroup(languageManager.t("Detected PD Details", "Dettagli PD rilevati")) {
                    ForEach(pdProperties) { property in
                        LabeledContent(property.key, value: property.value)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(port.portName)
    }

    @ViewBuilder
    private var stateStatus: some View {
        switch port.state {
        case .cableIdentityObserved:
            SemanticStatus(
                languageManager.t("Cable-side PD data observed", "Dati PD lato cavo osservati"),
                systemImage: "checkmark.circle.fill",
                tone: .success
            )
        case .connectedWithoutCableIdentity:
            SemanticStatus(
                languageManager.t("Cable e-marker not exposed", "E-marker del cavo non esposto"),
                systemImage: "questionmark.circle",
                tone: .neutral
            )
        case .inactive:
            SemanticStatus(
                languageManager.t("Port inactive", "Porta inattiva"),
                systemImage: "circle",
                tone: .neutral
            )
        }
    }

    @ViewBuilder
    private var observedAttention: some View {
        if port.authorizationRequired {
            SemanticStatus(
                languageManager.t(
                    "The port controller requires authorization.",
                    "Il controller della porta richiede autorizzazione."
                ),
                systemImage: "lock.trianglebadge.exclamationmark",
                tone: .warning
            )

            Button(
                languageManager.t("Open accessory settings", "Apri impostazioni accessori"),
                systemImage: "gearshape"
            ) {
                AccessoryAuthorizationSettings.open()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint(
                languageManager.t(
                    "Opens Privacy & Security in System Settings, where accessory access can be reviewed.",
                    "Apre Privacy e Sicurezza in Impostazioni di Sistema, dove puoi verificare l'accesso degli accessori."
                )
            )
        }

        if (port.overcurrentCount ?? 0) > 0 {
            SemanticStatus(
                languageManager.t(
                    "Overcurrent events reported by the port controller.",
                    "Il controller della porta ha segnalato eventi di sovracorrente."
                ),
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning
            )
        }

        if port.liquidDetected == true {
            SemanticStatus(
                languageManager.t(
                    "Liquid detection reported by the port controller.",
                    "Il controller della porta ha segnalato rilevamento liquidi."
                ),
                systemImage: "drop.triangle.fill",
                tone: .error
            )
        }
    }

    private var portSymbol: String {
        switch port.state {
        case .cableIdentityObserved: "cable.connector.horizontal"
        case .connectedWithoutCableIdentity: "cable.connector"
        case .inactive: "cable.connector.slash"
        }
    }

    private var portTone: SemanticStatusTone {
        switch port.state {
        case .cableIdentityObserved: .success
        case .connectedWithoutCableIdentity, .inactive: .neutral
        }
    }
}

private struct PDProperty: Identifiable {
    let key: String
    let value: String

    var id: String { key }
}
