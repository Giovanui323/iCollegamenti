import SwiftUI

struct HardwareEventLogView: View {
    @Environment(HardwareEventLog.self) private var hardwareEventLog
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hardwareEventLog.events.isEmpty {
                ContentUnavailableView(
                    languageManager.t("No Events", "Nessun Evento"),
                    systemImage: "list.bullet.rectangle",
                    description: Text(languageManager.t("No hardware events have been recorded.", "Nessun evento hardware è stato registrato."))
                )
            } else {
                List {
                    ForEach(hardwareEventLog.events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.timestamp.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(event.kind.rawValue)
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            Text(hardwareEventLog.eventDescription(event))
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(languageManager.t("Event Log", "Log Eventi"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive, action: {
                    hardwareEventLog.clear()
                }) {
                    Label(languageManager.t("Clear", "Svuota"), systemImage: "trash")
                }
            }
        }
    }
}
