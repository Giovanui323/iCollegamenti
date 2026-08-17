import SwiftUI
import CAVICore
import Charts

struct HDMICableLabelingView: View {
    @Environment(HDMICableHistoryStore.self) private var historyStore
    @Environment(LanguageManager.self) private var lm
    
    @State private var showingAddSheet = false
    @State private var newName = ""
    @State private var newManufacturer = ""
    @State private var newLength = ""
    @State private var newCertification = ""
    @State private var newLocation = ""
    @State private var newNotes = ""
    
    @State private var selectedCableId: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedCableId) {
                ForEach(historyStore.cables) { profile in
                    NavigationLink(value: profile.id) {
                        VStack(alignment: .leading) {
                            Text(profile.name).font(.headline)
                            Text(profile.declaredCertification ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(lm.t("Saved Cables", "Cavi Salvati"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        } detail: {
            if let id = selectedCableId, let profile = historyStore.cables.first(where: { $0.id == id }) {
                cableDetailView(profile: profile)
            } else {
                ContentUnavailableView(
                    lm.t("No Cable Selected", "Nessun Cavo Selezionato"),
                    systemImage: "cable.connector"
                )
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            addCableSheet
        }
    }
    
    @ViewBuilder
    private func cableDetailView(profile: HDMICableProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupBox(lm.t("Cable Details", "Dettagli Cavo")) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent(lm.t("Name", "Nome"), value: profile.name)
                        LabeledContent(lm.t("Manufacturer", "Produttore"), value: profile.manufacturer ?? "-")
                        LabeledContent(lm.t("Length", "Lunghezza"), value: profile.length ?? "-")
                        LabeledContent(lm.t("Certification", "Certificazione"), value: profile.declaredCertification ?? "-")
                        LabeledContent(lm.t("Location", "Posizione"), value: profile.location ?? "-")
                        LabeledContent(lm.t("Notes", "Note"), value: profile.notes ?? "-")
                    }
                }
                
                GroupBox(lm.t("Test History", "Cronologia Test")) {
                    let records = profile.testHistory
                    
                    if records.isEmpty {
                        Text(lm.t("No test history available.", "Nessuna cronologia di test disponibile."))
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(records) { record in
                            LineMark(
                                x: .value("Date", record.timestamp),
                                y: .value("Score", record.stabilityScore)
                            )
                            .symbol(Circle())
                        }
                        .frame(height: 200)
                        .padding()
                    }
                }
            }
            .padding()
        }
        .navigationTitle(profile.name)
    }
    
    private var addCableSheet: some View {
        NavigationStack {
            Form {
                Section(lm.t("Information", "Informazioni")) {
                    TextField(lm.t("Name", "Nome"), text: $newName)
                    TextField(lm.t("Manufacturer", "Produttore"), text: $newManufacturer)
                    TextField(lm.t("Length", "Lunghezza"), text: $newLength)
                    TextField(lm.t("Certification", "Certificazione"), text: $newCertification)
                }
                
                Section(lm.t("Additional", "Aggiuntivo")) {
                    TextField(lm.t("Location", "Posizione"), text: $newLocation)
                    TextField(lm.t("Notes", "Note"), text: $newNotes)
                }
            }
            .navigationTitle(lm.t("Add Cable", "Aggiungi Cavo"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(lm.t("Cancel", "Annulla")) { showingAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(lm.t("Save", "Salva")) {
                        let newProfile = HDMICableProfile(
                            name: newName,
                            manufacturer: newManufacturer.isEmpty ? nil : newManufacturer,
                            length: newLength.isEmpty ? nil : newLength,
                            declaredCertification: newCertification.isEmpty ? nil : newCertification,
                            location: newLocation.isEmpty ? nil : newLocation,
                            notes: newNotes.isEmpty ? nil : newNotes
                        )
                        historyStore.cables.append(newProfile)
                        showingAddSheet = false
                        clearForm()
                    }
                    .disabled(newName.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 400)
    }
    
    private func clearForm() {
        newName = ""
        newManufacturer = ""
        newLength = ""
        newCertification = ""
        newLocation = ""
        newNotes = ""
    }
}
