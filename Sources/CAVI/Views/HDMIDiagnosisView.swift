import SwiftUI
import CAVICore

struct HDMIDiagnosisView: View {
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(HDMIDisplayAnalysisService.self) private var hdmiAnalysis
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
                    
                    automaticDiagnosisSection(diagnosis: diagnosis)
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
    private func automaticDiagnosisSection(diagnosis: HDMIChainDiagnosis) -> some View {
        GroupBox(lm.t("Automatic Diagnosis", "Diagnosi Automatica")) {
            VStack(alignment: .leading, spacing: 16) {
                Text(diagnosis.naturalLanguageExplanation)
                    .font(.body)
                
                HStack(spacing: 24) {
                    scoreGauge(title: lm.t("Connection", "Connessione"), value: HDMIScoringEngine.connectionScore().overall)
                    scoreGauge(title: lm.t("Gaming", "Gaming"), value: HDMIScoringEngine.gamingScore().overall)
                    scoreGauge(title: lm.t("Professional", "Professionale"), value: HDMIScoringEngine.professionalScore().overall)
                }
                .padding(.top, 8)
            }
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private func scoreGauge(title: String, value: Int) -> some View {
        VStack {
            Gauge(value: Double(value), in: 0...100) {
                Text(title)
            } currentValueLabel: {
                Text("\(value)")
                    .foregroundStyle(value > 80 ? .green : (value > 50 ? .orange : .red))
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
