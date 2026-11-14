import SwiftUI
import CAVICore

/// Saved HDMI cables and a side-by-side comparison of what was measured with each.
struct HDMICableComparisonView: View {
    @Environment(HDMICableHistoryStore.self) private var historyStore
    @Environment(LanguageManager.self) private var lm

    @State private var cableAId: UUID?
    @State private var cableBId: UUID?
    @State private var showingAddSheet = false
    @State private var cablePendingDeletion: HDMICableProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SemanticStatus(
                lm.t(
                    "macOS cannot read anything from an HDMI cable, so cables are compared by what works through them. Add each cable here, connect it, run the tests in the Test tab and press \"Save to cable\". Then pick two cables below.",
                    "macOS non può leggere nulla da un cavo HDMI, quindi i cavi si confrontano in base a ciò che funziona attraverso di loro. Aggiungi qui ogni cavo, collegalo, esegui i test nella scheda Test e premi \"Salva sul cavo\". Poi scegli due cavi qui sotto."
                ),
                systemImage: "info.circle",
                tone: .neutral
            )

            savedCablesSection

            if historyStore.cables.count >= 2 {
                comparisonSection
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddHDMICableSheet { historyStore.addCable($0) }
        }
        .confirmationDialog(
            lm.t("Delete this cable and its test history?", "Eliminare questo cavo e la sua cronologia dei test?"),
            isPresented: Binding(get: { cablePendingDeletion != nil }, set: { if !$0 { cablePendingDeletion = nil } }),
            presenting: cablePendingDeletion
        ) { cable in
            Button(lm.t("Delete", "Elimina"), role: .destructive) {
                if cableAId == cable.id { cableAId = nil }
                if cableBId == cable.id { cableBId = nil }
                historyStore.deleteCable(id: cable.id)
            }
        }
    }

    private var savedCablesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(lm.t("Saved cables", "Cavi salvati"), systemImage: "cable.connector")
                        .font(.headline)
                    Spacer()
                    Button(lm.t("Add cable", "Aggiungi cavo"), systemImage: "plus") { showingAddSheet = true }
                }
                if historyStore.cables.isEmpty {
                    Text(lm.t("No cables yet. Add the first one to start keeping its results.", "Nessun cavo. Aggiungi il primo per iniziare a salvarne i risultati."))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(historyStore.cables) { cable in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cable.name).fontWeight(.medium)
                                Text(cableSubtitle(cable))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(lm.t("\(cable.testHistory.count) test(s)", "\(cable.testHistory.count) test"))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) { cablePendingDeletion = cable } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(lm.t("Delete cable", "Elimina cavo"))
                        }
                        .padding(.vertical, 2)
                        if cable.id != historyStore.cables.last?.id { Divider() }
                    }
                }
            }
            .padding(6)
        }
    }

    private func cableSubtitle(_ cable: HDMICableProfile) -> String {
        let parts = [cable.manufacturer, cable.length, cable.declaredCertification].compactMap { $0 }
        return parts.isEmpty ? lm.t("No details", "Nessun dettaglio") : parts.joined(separator: " · ")
    }

    private var comparisonSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Label(lm.t("Comparison", "Confronto"), systemImage: "arrow.left.arrow.right")
                    .font(.headline)
                HStack(spacing: 16) {
                    cablePicker(lm.t("Cable A", "Cavo A"), selection: $cableAId)
                    cablePicker(lm.t("Cable B", "Cavo B"), selection: $cableBId)
                }
                if let a = historyStore.cables.first(where: { $0.id == cableAId }),
                   let b = historyStore.cables.first(where: { $0.id == cableBId }) {
                    comparisonTable(a, b)
                } else {
                    Text(lm.t("Select two cables to compare.", "Seleziona due cavi per confrontarli."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(6)
        }
    }

    private func cablePicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text(lm.t("None", "Nessuno")).tag(UUID?.none)
            ForEach(historyStore.cables) { Text($0.name).tag(Optional($0.id)) }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }

    private func comparisonTable(_ a: HDMICableProfile, _ b: HDMICableProfile) -> some View {
        let best = { (cable: HDMICableProfile) in cable.testHistory.max { $0.maximumBandwidthGbps < $1.maximumBandwidthGbps } }
        let average = { (cable: HDMICableProfile) -> Int? in
            cable.testHistory.isEmpty ? nil : cable.testHistory.map(\.stabilityScore).reduce(0, +) / cable.testHistory.count
        }
        let disconnects = { (cable: HDMICableProfile) in cable.testHistory.map(\.disconnects).reduce(0, +) }
        let bandwidth = { (record: HDMICableTestRecord?) in
            record.map { $0.maximumBandwidthGbps > 0 ? String(format: "%.1f Gbps", $0.maximumBandwidthGbps) : "—" } ?? "—"
        }

        return Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
            GridRow {
                Text(lm.t("Metric", "Metrica")).font(.subheadline.weight(.semibold))
                Text(a.name).font(.subheadline.weight(.semibold))
                Text(b.name).font(.subheadline.weight(.semibold))
            }
            Divider()
            comparisonRow(lm.t("Tests saved", "Test salvati"), "\(a.testHistory.count)", "\(b.testHistory.count)")
            comparisonRow(lm.t("Max verified mode", "Modalità max verificata"), best(a)?.maximumVerifiedMode ?? "—", best(b)?.maximumVerifiedMode ?? "—")
            comparisonRow(lm.t("Max bandwidth", "Banda max"), bandwidth(best(a)), bandwidth(best(b)))
            comparisonRow(lm.t("Average stability", "Stabilità media"), average(a).map(String.init) ?? "—", average(b).map(String.init) ?? "—")
            comparisonRow(lm.t("Signal losses", "Perdite di segnale"), "\(disconnects(a))", "\(disconnects(b))")
        }
    }

    private func comparisonRow(_ metric: String, _ a: String, _ b: String) -> some View {
        GridRow {
            Text(metric).foregroundStyle(.secondary)
            Text(a).monospacedDigit()
            Text(b).monospacedDigit()
        }
    }
}

/// Form for a new cable. Only the name is required.
struct AddHDMICableSheet: View {
    @Environment(LanguageManager.self) private var lm
    @Environment(\.dismiss) private var dismiss
    let onSave: (HDMICableProfile) -> Void

    @State private var name = ""
    @State private var manufacturer = ""
    @State private var length = ""
    @State private var certification = ""
    @State private var location = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(lm.t("Add Cable", "Aggiungi Cavo")).font(.title2.weight(.semibold))
            Form {
                TextField(lm.t("Name", "Nome"), text: $name, prompt: Text(lm.t("e.g. Black 2 m cable", "es. Cavo nero 2 m")))
                TextField(lm.t("Manufacturer", "Produttore"), text: $manufacturer)
                TextField(lm.t("Length", "Lunghezza"), text: $length, prompt: Text("2 m"))
                TextField(lm.t("Certification on the box", "Certificazione sulla confezione"), text: $certification, prompt: Text("Ultra High Speed"))
                TextField(lm.t("Location", "Posizione"), text: $location)
                TextField(lm.t("Notes", "Note"), text: $notes)
            }
            HStack {
                Spacer()
                Button(lm.t("Cancel", "Annulla")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(lm.t("Save", "Salva")) {
                    let trimmed = { (text: String) -> String? in
                        let value = text.trimmingCharacters(in: .whitespaces)
                        return value.isEmpty ? nil : value
                    }
                    onSave(HDMICableProfile(
                        name: name.trimmingCharacters(in: .whitespaces),
                        manufacturer: trimmed(manufacturer),
                        length: trimmed(length),
                        declaredCertification: trimmed(certification),
                        location: trimmed(location),
                        notes: trimmed(notes)
                    ))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
