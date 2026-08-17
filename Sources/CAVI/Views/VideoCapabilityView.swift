import SwiftUI
import CAVICore

struct VideoCapabilityView: View {
    let sustainedWriteMBps: Double
    let languageManager: LanguageManager

    private var assessment: VideoCapabilityAssessment {
        VideoCapabilityEstimator.assess(sustainedWriteMBps: sustainedWriteMBps)
    }

    var body: some View {
        GroupBox(languageManager.t("Video Editing Capability", "Compatibilità montaggio video")) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(assessment.capabilities, id: \.workflow) { capability in
                    HStack {
                        Text(workflowTitle(capability.workflow))
                        Spacer()
                        Text(statusTitle(capability.status))
                            .foregroundStyle(statusColor(capability.status))
                    }
                }
                LabeledContent(languageManager.t("Estimated 4K streams", "Stream 4K stimati"), value: "\(assessment.maximum4KStreams)")
                Text(languageManager.t(
                    "Indicative estimate from measured write speed; codec, frame rate, color depth, editing software, and sustained performance can change the requirement.",
                    "Stima indicativa dalla velocità di scrittura misurata; codec, frame rate, profondità colore, software e prestazioni sostenute possono cambiare il requisito."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func workflowTitle(_ workflow: VideoWorkflow) -> String {
        switch workflow {
        case .proRes4K422: "4K ProRes 422"
        case .proRes6K422: "6K ProRes 422"
        case .proRes8KRaw: "8K ProRes RAW"
        }
    }

    private func statusTitle(_ status: VideoCapabilityStatus) -> String {
        switch status {
        case .supported: languageManager.t("Supported", "Supportato")
        case .marginal: languageManager.t("Marginal", "Al limite")
        case .notRecommended: languageManager.t("Not recommended", "Non consigliato")
        }
    }

    private func statusColor(_ status: VideoCapabilityStatus) -> Color {
        switch status {
        case .supported: .green
        case .marginal: .orange
        case .notRecommended: .red
        }
    }
}
