import SwiftUI
import CAVICore

struct HDMIDiagnosisView: View {
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(HDMIDisplayAnalysisService.self) private var hdmiAnalysis
    @Environment(EDIDReaderService.self) private var edidReader
    @Environment(LanguageManager.self) private var lm

    var body: some View {
        ScrollView {
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
                    
                    automaticDiagnosisSection(diagnosis: diagnosis, config: config, edid: edidReader.parsedEDID(for: display.displayID))
                    wizardSection(diagnosis: diagnosis)
                    
                } else {
                    Text(lm.t("No display selected", "Nessun display selezionato"))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func automaticDiagnosisSection(diagnosis: HDMIChainDiagnosis, config: HDMISignalConfiguration?, edid: ParsedEDID?) -> some View {
        GroupBox(lm.t("Automatic Diagnosis", "Diagnosi Automatica")) {
            VStack(alignment: .leading, spacing: 16) {
                Text(diagnosis.naturalLanguageExplanation)
                    .font(.body)
                
                // Scores come only from the active signal and the EDID. Connection stability
                // is not measured here, so it is shown as unavailable instead of a perfect 100.
                HStack(spacing: 24) {
                    scoreGauge(title: lm.t("Connection", "Connessione"), value: nil)
                    scoreGauge(title: lm.t("Gaming", "Gaming"), value: config.map { HDMIScoringEngine.observedGamingScore(signal: $0, edid: edid).overall })
                    scoreGauge(title: lm.t("Professional", "Professionale"), value: config.map { HDMIScoringEngine.observedProfessionalScore(signal: $0, edid: edid).overall })
                }
                .padding(.top, 8)
            }
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private func scoreGauge(title: String, value: Int?) -> some View {
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
                        .help(lm.t("Not measured", "Non misurato"))
                }
            }
            .gaugeStyle(.accessoryCircular)
            .scaleEffect(1.2)
            
            Text(title)
                .font(.caption)
                .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private func wizardSection(diagnosis: HDMIChainDiagnosis) -> some View {
        GroupBox(lm.t("Diagnosis Wizard", "Assistente Diagnosi")) {
            VStack(alignment: .leading, spacing: 16) {
                Text(lm.t("Checklist", "Lista di controllo"))
                    .font(.headline)
                
                ForEach(diagnosis.wizardSteps, id: \.name) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: step.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(step.passed ? .green : .red)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.name)
                                .font(.subheadline.weight(.medium))
                            Text(step.resultDescription)
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
}
