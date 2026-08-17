import SwiftUI

enum SemanticStatusTone {
    case neutral
    case success
    case warning
    case error

    var foregroundStyle: AnyShapeStyle {
        switch self {
        case .neutral: AnyShapeStyle(.secondary)
        case .success: AnyShapeStyle(.green)
        case .warning: AnyShapeStyle(.orange)
        case .error: AnyShapeStyle(.red)
        }
    }
}

struct SemanticStatus: View {
    let title: String
    let systemImage: String
    let tone: SemanticStatusTone

    init(_ title: String, systemImage: String, tone: SemanticStatusTone = .neutral) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(tone.foregroundStyle)
            .accessibilityElement(children: .combine)
    }
}

struct NativeSectionHeader: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A manual catalog selection. It deliberately does not infer the physical cable
/// from a display or power measurement: saving the parent result is the user's
/// explicit association.
struct CableCatalogSelection: View {
    @Environment(TestHistoryStore.self) private var historyStore
    @Environment(LanguageManager.self) private var languageManager

    @Binding var selectedCableID: UUID?
    @Binding var cableName: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(languageManager.t("Registered cable", "Cavo registrato"), selection: $selectedCableID) {
                Text(languageManager.t("Register a new cable", "Registra un nuovo cavo"))
                    .tag(UUID?.none)
                ForEach(historyStore.cableProfiles) { cable in
                    Text("\(cable.code) — \(cable.name)")
                        .tag(Optional(cable.id))
                }
            }
            .onChange(of: selectedCableID) { _, cableID in
                if let cable = historyStore.cableProfile(id: cableID) {
                    cableName = cable.name
                }
            }

            TextField(prompt, text: $cableName)
                .textFieldStyle(.roundedBorder)

            if let cable = historyStore.cableProfile(id: selectedCableID) {
                LabeledContent(languageManager.t("Unique code", "Codice univoco"), value: cable.code)
                    .font(.caption)
                    .textSelection(.enabled)
            }
        }
    }
}
