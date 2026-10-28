import SwiftUI
import CAVICore

struct HDMIDiagnosisView: View {
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(HDMIDisplayAnalysisService.self) private var hdmiAnalysis
    @Environment(HDMIStressTestService.self) private var stressTest
    @Environment(EDIDReaderService.self) private var edidReader
    @Environment(LanguageManager.self) private var lm

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let display = hdmiService.selectedDisplay {
                    let config = hdmiAnalysis.currentConfiguration(for: display.displayID)
                    let edid = edidReader.parsedEDID(for: display.displayID)
                    let stress = stressTest.result(for: display.displayID)

                    let diagnosis = HDMIChainAnalyzer.analyze(
                        macGPU: "Apple Silicon",
                        portType: "HDMI",
                        adapterInfo: nil,
                        testedCableBandwidth: nil,
                        displayMaxMode: "Unknown",
                        currentMode: "\(config?.width ?? 0)x\(config?.height ?? 0)"
                    )

                    automaticDiagnosisSection(diagnosis: diagnosis, config: config, edid: edid, stress: stress)
                    wizardSection(items: HDMIDiagnosisChecklist.items(signal: config, edid: edid, stress: stress))
                } else {
                    Text(lm.t("No display selected", "Nessun display selezionato"))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func automaticDiagnosisSection(diagnosis: HDMIChainDiagnosis, config: HDMISignalConfiguration?, edid: ParsedEDID?, stress: HDMIStressTestResult?) -> some View {
        GroupBox(lm.t("Automatic Diagnosis", "Diagnosi Automatica")) {
            VStack(alignment: .leading, spacing: 16) {
                Text(diagnosis.naturalLanguageExplanation)
                    .font(.body)

                // Scores come only from the active signal, the EDID and a completed stress test.
                // Without a stress test the connection is not measured, so it shows as unavailable.
                let connection = HDMIScoringEngine.observedConnectionScore(signal: config, edid: edid, stress: stress)
                HStack(spacing: 24) {
                    scoreGauge(
                        title: lm.t("Connection", "Connessione"),
                        value: connection?.overall,
                        unavailableHelp: lm.t("Run a stress test to measure the connection.", "Esegui uno stress test per misurare la connessione.")
                    )
                    scoreGauge(title: lm.t("Gaming", "Gaming"), value: config.map { HDMIScoringEngine.observedGamingScore(signal: $0, edid: edid).overall })
                    scoreGauge(title: lm.t("Professional", "Professionale"), value: config.map { HDMIScoringEngine.observedProfessionalScore(signal: $0, edid: edid).overall })
                }
                .padding(.top, 8)

                if let connection, !connection.bandwidthObserved {
                    Text(lm.t(
                        "The display's EDID does not state a link capacity, so bandwidth headroom is not part of the connection score.",
                        "L'EDID del monitor non dichiara la capacità del link, quindi il margine di banda non è incluso nel punteggio di connessione."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func scoreGauge(title: String, value: Int?, unavailableHelp: String? = nil) -> some View {
        VStack {
            Gauge(value: Double(value ?? 0), in: 0...100) {
                Text(title)
            } currentValueLabel: {
                if let value {
                    Text("\(value)")
                        .foregroundStyle(value > 80 ? .green : (value > 50 ? .orange : .red))
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .gaugeStyle(.accessoryCircular)
            .scaleEffect(1.2)
            .help(value == nil ? (unavailableHelp ?? lm.t("Not measured", "Non misurato")) : "")

            Text(title)
                .font(.caption)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func wizardSection(items: [HDMIChecklistItem]) -> some View {
        GroupBox(lm.t("Diagnosis Wizard", "Assistente Diagnosi")) {
            VStack(alignment: .leading, spacing: 16) {
                Text(lm.t("Checklist", "Lista di controllo"))
                    .font(.headline)

                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        checklistIcon(item.status)
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(checklistTitle(item.kind))
                                .font(.subheadline.weight(.medium))
                            Text(checklistDescription(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func checklistIcon(_ status: HDMIChecklistStatus) -> some View {
        Group {
            switch status {
            case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .attention: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .unavailable: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            }
        }
    }

    private func checklistTitle(_ kind: HDMIChecklistItemKind) -> String {
        switch kind {
        case .edidIntegrity: lm.t("Display identification (EDID)", "Identificazione del monitor (EDID)")
        case .nativeResolution: lm.t("Native resolution", "Risoluzione nativa")
        case .linkBandwidth: lm.t("Link bandwidth", "Banda del collegamento")
        case .chromaQuality: lm.t("Colour sampling", "Campionamento colore")
        case .hdr: lm.t("HDR", "HDR")
        case .signalStability: lm.t("Signal stability", "Stabilità del segnale")
        }
    }

    private func checklistDescription(_ item: HDMIChecklistItem) -> String {
        let observed = item.observed ?? "—"
        let expected = item.expected ?? "—"
        switch (item.kind, item.status) {
        case (.edidIntegrity, .passed):
            return lm.t("EDID \(observed) read with a valid checksum.", "EDID \(observed) letto con checksum valido.")
        case (.edidIntegrity, .failed):
            return lm.t("The EDID checksum is wrong: the data may be corrupted by the cable, adapter or display.", "Il checksum dell'EDID è errato: i dati potrebbero essere corrotti da cavo, adattatore o monitor.")
        case (.edidIntegrity, _):
            return lm.t("macOS did not expose this display's EDID.", "macOS non ha esposto l'EDID di questo monitor.")

        case (.nativeResolution, .passed):
            return lm.t("Running at \(observed), the display's native resolution.", "In uso a \(observed), la risoluzione nativa del monitor.")
        case (.nativeResolution, .attention):
            return lm.t("Running at \(observed); the display is native \(expected). Check the resolution setting or the cable.", "In uso a \(observed); il monitor è nativo \(expected). Controlla l'impostazione di risoluzione o il cavo.")
        case (.nativeResolution, _):
            return lm.t("Native resolution not available.", "Risoluzione nativa non disponibile.")

        case (.linkBandwidth, .passed):
            return lm.t("The signal needs \(observed) of the \(expected) the display accepts.", "Il segnale richiede \(observed) dei \(expected) accettati dal monitor.")
        case (.linkBandwidth, .attention):
            return lm.t("The signal needs \(observed), close to the \(expected) the display accepts.", "Il segnale richiede \(observed), vicino ai \(expected) accettati dal monitor.")
        case (.linkBandwidth, .failed):
            return lm.t("The signal needs \(observed), more than the \(expected) the display states; compression or subsampling is likely in use.", "Il segnale richiede \(observed), più dei \(expected) dichiarati dal monitor: probabilmente è attiva compressione o sottocampionamento.")
        case (.linkBandwidth, _):
            return lm.t("The display does not state a link capacity in its EDID.", "Il monitor non dichiara la capacità del link nell'EDID.")

        case (.chromaQuality, .passed):
            return lm.t("Full colour sampling (\(observed)).", "Campionamento colore completo (\(observed)).")
        case (.chromaQuality, .attention):
            return lm.t("Subsampled colour (\(observed)): text may look soft. Often caused by a bandwidth limit.", "Colore sottocampionato (\(observed)): il testo può apparire sfocato. Spesso dovuto a un limite di banda.")
        case (.chromaQuality, _):
            return lm.t("Signal not analysed yet.", "Segnale non ancora analizzato.")

        case (.hdr, .passed):
            return lm.t("HDR is active.", "HDR attivo.")
        case (.hdr, .attention):
            return lm.t("The display supports HDR, but the signal is SDR. Enable HDR in Displays settings if you need it.", "Il monitor supporta l'HDR, ma il segnale è SDR. Attiva l'HDR nelle impostazioni Monitor se ti serve.")
        case (.hdr, _):
            return lm.t("The display does not advertise HDR.", "Il monitor non dichiara il supporto HDR.")

        case (.signalStability, .passed):
            return lm.t("No signal loss during the \(expected) s stress test.", "Nessuna perdita di segnale durante lo stress test di \(expected) s.")
        case (.signalStability, .attention):
            return lm.t("No signal loss in \(expected) s, but the mode or refresh rate changed.", "Nessuna perdita di segnale in \(expected) s, ma la modalità o la frequenza è cambiata.")
        case (.signalStability, .failed):
            return lm.t("\(observed) signal loss(es) during the \(expected) s stress test.", "\(observed) perdita/e di segnale durante lo stress test di \(expected) s.")
        case (.signalStability, _):
            return lm.t("Run a stress test to check stability.", "Esegui uno stress test per verificare la stabilità.")
        }
    }
}
