import SwiftUI
import UniformTypeIdentifiers
import Charts

struct CableLeaderboardView: View {
    @Environment(TestHistoryStore.self) private var historyStore
    @Environment(HardwareEventLog.self) private var hardwareEventLog
    @Environment(LanguageManager.self) private var languageManager
    
    @State private var searchText = ""
    @State private var selectedCategoryFilter: CableCategory? = nil
    @State private var onlyBenchmarked = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var useStartDate = false
    @State private var sortOrder = [KeyPathComparator(\CableTestResult.linkSpeedBps, order: .reverse)]
    @State private var selection: Set<CableTestResult.ID> = []
    
    @State private var showingDeleteSelectedConfirmation = false
    @State private var showingClearAllConfirmation = false
    @State private var showingClearEventLogConfirmation = false
    @State private var showingImporter = false
    @State private var pendingImport: Data?
    @State private var showingImportConfirmation = false
    @State private var importMessage: String?
    
    @State private var showingRenameAlert = false
    @State private var itemToRename: CableTestResult? = nil
    @State private var renameText: String = ""
    
    var filteredAndSortedResults: [CableTestResult] {
        let categoryFiltered = historyStore.results(forCategory: selectedCategoryFilter)
        let filtered = categoryFiltered.filter { result in
            let matchesSearch = searchText.isEmpty
                || cableDisplayName(for: result).localizedCaseInsensitiveContains(searchText)
                || cableCode(for: result)?.localizedCaseInsensitiveContains(searchText) == true
                || result.deviceName.localizedCaseInsensitiveContains(searchText)
            let matchesBenchmark = !onlyBenchmarked || result.benchmarkReadMBps != nil || result.benchmarkWriteMBps != nil
            return matchesSearch && matchesBenchmark && (!useStartDate || result.timestamp >= startDate)
        }
        return filtered.sorted(using: sortOrder)
    }
    
    private var maxSpeedInResults: UInt64 {
        historyStore.testResults.filter { $0.category == .data }.map(\.linkSpeedBps).max() ?? 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            resultSummary
            filterControls
            
            if filteredAndSortedResults.isEmpty {
                emptyState
            } else {
                resultsTable
                let selectedResults = filteredAndSortedResults.filter { selection.contains($0.id) }
                if selectedResults.count >= 2 {
                    comparisonSection(selectedResults)
                }
                if selection.count == 1, let result = filteredAndSortedResults.first(where: { $0.id == selection.first }) {
                    resultDetail(result)
                }
            }

            eventLogSection
            advancedBenchmarkHistorySection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The Tahoe sidebar can visually overhang the split-view boundary. Keep
        // interactive content clear of that glass surface.
        .padding(.vertical)
        .padding(.trailing)
        .padding(.leading, 32)
        .searchable(
            text: $searchText,
            prompt: languageManager.t("Search cable or device", "Cerca cavo o dispositivo")
        )
        .confirmationDialog(
            languageManager.t("Confirm Deletion", "Conferma eliminazione"),
            isPresented: $showingDeleteSelectedConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                languageManager.t("Delete \(selection.count) \(selection.count == 1 ? "item" : "items")", "Elimina \(selection.count) \(selection.count == 1 ? "elemento" : "elementi")"),
                role: .destructive
            ) {
                deleteSelectedItems(selection)
            }
            Button(languageManager.t("Cancel", "Annulla"), role: .cancel) {}
        } message: {
            Text(languageManager.t(
                "Are you sure you want to delete \(selection.count) selected item(s) from history? This cannot be undone.",
                "Sei sicuro di voler eliminare \(selection.count) \(selection.count == 1 ? "elemento selezionato" : "elementi selezionati") dalla cronologia? L'operazione non può essere annullata."
            ))
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = languageManager.t("Cannot access selected file.", "Impossibile accedere al file selezionato.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            pendingImport = try? Data(contentsOf: url)
            showingImportConfirmation = pendingImport != nil
            if pendingImport == nil {
                importMessage = languageManager.t("Cannot read selected file.", "Impossibile leggere il file selezionato.")
            }
        }
        .confirmationDialog(languageManager.t("Import history?", "Importare la cronologia?"), isPresented: $showingImportConfirmation) {
            Button(languageManager.t("Import", "Importa"), role: .none) { importPendingResults() }
            Button(languageManager.t("Cancel", "Annulla"), role: .cancel) { pendingImport = nil }
        } message: {
            Text(languageManager.t(
                "New records will be added to existing history; existing IDs will not be duplicated.",
                "I record nuovi saranno aggiunti alla cronologia esistente; quelli con lo stesso ID non verranno duplicati."
            ))
        }
        .alert(languageManager.t("Import", "Importazione"), isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .confirmationDialog(
            languageManager.t("Clear History", "Svuota cronologia"),
            isPresented: $showingClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(languageManager.t("Delete all data", "Elimina tutti i dati"), role: .destructive) {
                clearAllHistory()
            }
            Button(languageManager.t("Cancel", "Annulla"), role: .cancel) {}
        } message: {
            Text(languageManager.t(
                "Are you sure you want to delete all test history? All saved records will be permanently removed.",
                "Sei sicuro di voler eliminare l'intera cronologia dei test? Tutti i risultati salvati verranno rimossi permanentemente."
            ))
        }
        .confirmationDialog(
            languageManager.t("Clear Event Log", "Svuota log eventi"),
            isPresented: $showingClearEventLogConfirmation,
            titleVisibility: .visible
        ) {
            Button(languageManager.t("Clear event log", "Svuota log eventi"), role: .destructive) {
                hardwareEventLog.clear()
            }
            Button(languageManager.t("Cancel", "Annulla"), role: .cancel) {}
        } message: {
            Text(languageManager.t(
                "This removes locally stored hardware events. It does not change your saved test history.",
                "Questa operazione elimina gli eventi hardware salvati localmente. Non modifica la cronologia dei test."
            ))
        }
        .alert(languageManager.t("Rename Cable", "Rinomina Cavo"), isPresented: $showingRenameAlert) {
            TextField(languageManager.t("Cable name (e.g. Anker USB-C 10Gbps)", "Nome cavo (es. Anker USB-C 10Gbps)"), text: $renameText)
            Button(languageManager.t("Save", "Salva")) {
                if let item = itemToRename {
                    let clean = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty {
                        if let cableID = item.cableID {
                            historyStore.renameCable(id: cableID, newName: clean)
                        } else {
                            historyStore.renameTestResult(id: item.id, newLabel: clean)
                        }
                    }
                }
                itemToRename = nil
            }
            Button(languageManager.t("Cancel", "Annulla"), role: .cancel) {
                itemToRename = nil
            }
        } message: {
            Text(languageManager.t(
                "Enter a commercial name or custom label for this cable.",
                "Inserisci il nome commerciale o un'etichetta personalizzata per questo cavo."
            ))
        }
    }
    
    private var resultSummary: some View {
        Text(resultSummaryText)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventLogSection: some View {
        GroupBox(languageManager.t("Technical Event Log", "Log eventi tecnici")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(languageManager.t(
                    "Attach, detach, benchmark, protocol, and negotiated-link events are kept locally on this Mac.",
                    "Gli eventi di collegamento, scollegamento, benchmark, protocollo e link negoziato sono conservati localmente su questo Mac."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                if hardwareEventLog.events.isEmpty {
                    Text(languageManager.t("No events recorded in this session yet.", "Nessun evento registrato in questa sessione."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(hardwareEventLog.events.prefix(30)) { event in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Text(hardwareEventLog.eventDescription(event))
                                        .font(.caption)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                    HStack {
                        Text(languageManager.t("Most recent 30 events", "Ultimi 30 eventi"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(languageManager.t("Clear Log", "Svuota log"), role: .destructive) {
                            showingClearEventLogConfirmation = true
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var advancedBenchmarkHistorySection: some View {
        GroupBox(languageManager.t("Advanced Benchmark History", "Cronologia benchmark avanzati")) {
            if historyStore.advancedBenchmarkRecords.isEmpty {
                Text(languageManager.t(
                    "Advanced workloads will appear here after they complete.",
                    "I carichi avanzati compariranno qui dopo il completamento."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(historyStore.advancedBenchmarkRecords.prefix(20)) { record in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.deviceName)
                                Text(advancedBenchmarkSummary(record))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(record.timestamp, format: .dateTime.day().month().year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if record.id != historyStore.advancedBenchmarkRecords.prefix(20).last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func advancedBenchmarkSummary(_ record: AdvancedBenchmarkRecord) -> String {
        let workload = record.result.configuration.workload.rawValue
        let size = ByteCountFormatter.string(fromByteCount: Int64(record.result.configuration.preset.sizeBytes), countStyle: .file)
        let read = record.result.samples.reversed().compactMap(\.readMBps).first
        let write = record.result.samples.reversed().compactMap(\.writeMBps).first
        let performance = [read.map { String(format: "R %.1f MB/s", $0) }, write.map { String(format: "W %.1f MB/s", $0) }]
            .compactMap { $0 }
            .joined(separator: " · ")
        return [workload, size, performance].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func comparisonSection(_ results: [CableTestResult]) -> some View {
        GroupBox(languageManager.t("Selected Comparison", "Confronto selezionati")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(languageManager.t(
                    "Compare the observed link and benchmark values collected under their saved configurations.",
                    "Confronta link osservato e benchmark raccolti con le rispettive configurazioni salvate."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(results) { result in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cableDisplayName(for: result))
                                .fontWeight(.bold)
                            Text(result.deviceName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            // Overall rating from rating
                            HStack {
                                Text(result.rating.emoji)
                                Text(result.rating.label)
                                    .font(.caption)
                                    .foregroundStyle(result.rating.color)
                            }
                            
                            // Stability score
                            if let stability = historyStore.analyzeStability(forCable: result.cableLabel).isStable ? 100 : 50 {
                                Text(languageManager.t("Stability: \(stability)/100", "Stabilità: \(stability)/100"))
                                    .font(.caption)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(result.primaryMeasurement.value)
                                .monospacedDigit()
                            
                            if let read = result.benchmarkReadMBps, let write = result.benchmarkWriteMBps {
                                Text(String(format: "R %.1f · W %.1f MB/s", read, write))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            } else {
                                Text(languageManager.t("No benchmark", "Nessun benchmark"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Power delivery info
                            if result.category == .charging {
                                Text(languageManager.t("Power Delivery", "Power Delivery"))
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else if let power = result.portInfo, power.contains("W") {
                                Text(power)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if result.id != results.last?.id { Divider() }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var resultSummaryText: String {
        let total = historyStore.testResults.count
        let visible = filteredAndSortedResults.count
        if visible == total {
            return languageManager.t("\(total) saved results", "\(total) risultati salvati")
        }
        return languageManager.t("\(visible) of \(total) results", "\(visible) di \(total) risultati")
    }

    private var filterControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                categoryPicker
                benchmarkToggle
                dateFilterToggle
                Spacer(minLength: 4)
                historyActions
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    categoryPicker
                    Spacer(minLength: 4)
                    historyActions
                }
                HStack(spacing: 10) {
                    benchmarkToggle
                    dateFilterToggle
                    Spacer()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) { categoryPicker; historyActions }
                HStack(spacing: 10) {
                    benchmarkToggle
                    dateFilterToggle
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryPicker: some View {
        Picker(languageManager.t("Category", "Categoria"), selection: $selectedCategoryFilter) {
            Text(languageManager.t("All (\(historyStore.testResults.count))", "Tutte (\(historyStore.testResults.count))")).tag(CableCategory?.none)
            ForEach(CableCategory.allCases) { cat in
                Label(cat.localizedName(using: languageManager), systemImage: cat.symbol).tag(Optional(cat))
            }
        }
        .pickerStyle(.menu)
        .frame(width: 145)
    }

    private var benchmarkToggle: some View {
        Toggle(languageManager.t("With benchmark", "Con benchmark"), isOn: $onlyBenchmarked)
            .toggleStyle(.checkbox)
    }

    private var dateFilterToggle: some View {
        HStack(spacing: 6) {
            Toggle(languageManager.t("From", "Dal"), isOn: $useStartDate)
                .toggleStyle(.checkbox)
            if useStartDate {
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .frame(width: 105)
            }
        }
    }

    private var historyActions: some View {
        HStack(spacing: 8) {
            if !selection.isEmpty {
                Button(role: .destructive, action: { showingDeleteSelectedConfirmation = true }) {
                    Label(languageManager.t("Delete (\(selection.count))", "Elimina (\(selection.count))"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .labelStyle(.iconOnly)
                .help(languageManager.t("Delete selected results", "Elimina i risultati selezionati"))
                .accessibilityLabel(languageManager.t("Delete selected results", "Elimina i risultati selezionati"))
            }
            
            Menu {
                Button(action: { showingImporter = true }) {
                    Label(languageManager.t("Import JSON…", "Importa JSON…"), systemImage: "square.and.arrow.down")
                }
                Divider()
                if !historyStore.testResults.isEmpty {
                    Button(role: .destructive, action: { showingClearAllConfirmation = true }) {
                        Label(languageManager.t("Clear all history", "Svuota tutta la cronologia"), systemImage: "trash.slash")
                    }
                }
            } label: {
                Label(languageManager.t("Manage History", "Gestisci cronologia"), systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderedButton)
            .help(languageManager.t("Import or clear saved results", "Importa o svuota i risultati salvati"))
        }
    }

    private func resultDetail(_ result: CableTestResult) -> some View {
        GroupBox(languageManager.t("Result Details", "Dettaglio risultato")) {
            VStack(alignment: .leading, spacing: 8) {
                if let cable = historyStore.cableProfile(id: result.cableID) {
                    LabeledContent(languageManager.t("Cable", "Cavo"), value: cable.name)
                    LabeledContent(languageManager.t("Unique code", "Codice univoco"), value: cable.code)
                        .textSelection(.enabled)
                } else {
                    HStack(spacing: 8) {
                        Text(languageManager.t("Cable Label:", "Etichetta Cavo:"))
                            .font(.subheadline.weight(.semibold))
                        TextField(languageManager.t("Cable name (e.g. Anker USB-C 10Gbps)", "Nome del cavo (es. Anker USB-C 10Gbps)"), text: Binding(
                            get: { result.cableLabel },
                            set: { newLabel in
                                let clean = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !clean.isEmpty {
                                    historyStore.renameTestResult(id: result.id, newLabel: clean)
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
                
                LabeledContent(languageManager.t("Connected device", "Dispositivo collegato"), value: result.deviceName)
                LabeledContent(languageManager.t("Configuration", "Configurazione"), value: result.topologyDescription ?? languageManager.t("Not available", "Non disponibile"))
                LabeledContent(languageManager.t("Port", "Porta"), value: result.portInfo ?? languageManager.t("Not available", "Non disponibile"))
                LabeledContent(languageManager.t("Hub", "Hub"), value: result.hubInfo ?? languageManager.t("Not available", "Non disponibile"))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.t("Personal notes:", "Note personali:"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: Binding(get: { result.userNotes ?? "" }, set: { historyStore.updateNotes(id: result.id, notes: $0) }))
                        .frame(minHeight: 54)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }
                
                historicalTrendSection(for: result)
            }
        }
    }
    
    @ViewBuilder
    private func historicalTrendSection(for result: CableTestResult) -> some View {
        let historicalResults = historyStore.getResultsForCable(label: result.cableLabel).sorted(by: { $0.timestamp < $1.timestamp })
        if historicalResults.count > 1 {
            Divider()
            Text(languageManager.t("Historical Trend", "Tendenza Storica"))
                .font(.headline)
            
            // Check for degradation
            if let first = historicalResults.first, let last = historicalResults.last {
                if last.linkSpeedBps < first.linkSpeedBps {
                    Text(languageManager.t("⚠️ Warning: Link speed has degraded over time.", "⚠️ Attenzione: La velocità del link si è degradata nel tempo."))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let firstRead = first.benchmarkReadMBps, let lastRead = last.benchmarkReadMBps, lastRead < firstRead * 0.8 {
                    Text(languageManager.t("⚠️ Warning: Benchmark speed has significantly degraded.", "⚠️ Attenzione: La velocità del benchmark si è notevolmente degradata."))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            Chart {
                ForEach(historicalResults) { res in
                    LineMark(
                        x: .value(languageManager.t("Date", "Data"), res.timestamp),
                        y: .value(languageManager.t("Speed Bps", "Velocità Bps"), res.linkSpeedBps)
                    )
                    .foregroundStyle(.blue)
                    .symbol(Circle())
                }
            }
            .frame(height: 120)
            
            let benchmarkedResults = historicalResults.filter { $0.benchmarkReadMBps != nil }
            if benchmarkedResults.count > 1 {
                Chart {
                    ForEach(benchmarkedResults) { res in
                        if let read = res.benchmarkReadMBps {
                            LineMark(
                                x: .value(languageManager.t("Date", "Data"), res.timestamp),
                                y: .value(languageManager.t("Read MB/s", "Lettura MB/s"), read)
                            )
                            .foregroundStyle(.green)
                            .symbol(Circle())
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(languageManager.t("No results in history", "Nessun risultato in cronologia"))
                .font(.headline.weight(.semibold))
            Text(languageManager.t(
                "Run a USB benchmark or save a video/charging test to find it here.",
                "Esegui un benchmark USB o salva un risultato video o di ricarica per trovarlo qui."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Results Table
    
    private var resultsTable: some View {
        Table(filteredAndSortedResults, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(languageManager.t("Cable", "Cavo"), value: \.cableLabel) { result in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: result.category.symbol)
                            .foregroundStyle(.secondary)
                        if result.category == .data && result.linkSpeedBps == maxSpeedInResults && maxSpeedInResults > 0 {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        Text(cableDisplayName(for: result))
                            .fontWeight(result.category == .data && result.linkSpeedBps == maxSpeedInResults ? .bold : .regular)
                    }
                    if let cableCode = cableCode(for: result) {
                        Text(cableCode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(languageManager.t("Not registered", "Non registrato"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 170, ideal: 230)
            
            TableColumn(languageManager.t("Observed", "Rilevato")) { result in
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.primaryMeasurement.value)
                        .monospacedDigit()
                    Text(result.usbRating?.connectionType ?? result.primaryMeasurement.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 120, ideal: 155)

            TableColumn(languageManager.t("Benchmark", "Benchmark")) { result in
                benchmarkSummary(for: result)
            }
            .width(min: 120, ideal: 155)
            
            TableColumn(languageManager.t("Device", "Dispositivo"), value: \.deviceName) { result in
                Text(result.deviceName)
                    .font(.caption)
            }
            .width(min: 120, ideal: 170)
            
            TableColumn(languageManager.t("Date", "Data"), value: \.timestamp) { result in
                Text(result.timestamp, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 135, max: 150)
        }
        .contextMenu(forSelectionType: CableTestResult.ID.self) { items in
            let targetIDs = items.isEmpty ? selection : items
            if targetIDs.count == 1, let id = targetIDs.first, let item = historyStore.testResults.first(where: { $0.id == id }) {
                Button(action: {
                    itemToRename = item
                    renameText = cableDisplayName(for: item)
                    showingRenameAlert = true
                }) {
                    Label(languageManager.t("Rename cable...", "Rinomina cavo..."), systemImage: "pencil")
                }
                Divider()
            }
            if !targetIDs.isEmpty {
                Button(role: .destructive, action: {
                    deleteSelectedItems(targetIDs)
                }) {
                    Label(
                        targetIDs.count == 1 
                            ? languageManager.t("Delete from history", "Elimina dal registro") 
                            : languageManager.t("Delete \(targetIDs.count) items", "Elimina \(targetIDs.count) elementi"),
                        systemImage: "trash"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func benchmarkSummary(for result: CableTestResult) -> some View {
        if result.benchmarkReadMBps != nil || result.benchmarkWriteMBps != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let read = result.benchmarkReadMBps {
                    Text("R \(String(format: "%.1f MB/s", read))")
                }
                if let write = result.benchmarkWriteMBps {
                    Text("S \(String(format: "%.1f MB/s", write))")
                }
            }
            .font(.caption.monospacedDigit().weight(.semibold))
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Selection & Deletion Helpers
    
    private func deleteSelectedItems(_ ids: Set<CableTestResult.ID>) {
        historyStore.deleteTestResults(ids: ids)
        selection.subtract(ids)
    }
    
    private func clearAllHistory() {
        historyStore.clearAllTestResults()
        selection.removeAll()
    }

    private func cableDisplayName(for result: CableTestResult) -> String {
        historyStore.cableProfile(id: result.cableID)?.name ?? result.cableLabel
    }

    private func cableCode(for result: CableTestResult) -> String? {
        historyStore.cableProfile(id: result.cableID)?.code
    }

    private func importPendingResults() {
        defer { pendingImport = nil }
        guard let pendingImport else { return }
        do {
            let count = try historyStore.importResults(from: pendingImport)
            importMessage = languageManager.t("Imported \(count) new results.", "Importati \(count) nuovi risultati.")
        } catch {
            importMessage = error.localizedDescription
        }
    }
    
    // MARK: - Export Actions
    
    private func exportToMarkdown() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.plainText]
        savePanel.nameFieldStringValue = "Report_iCollegamenti.md"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let data = historyStore.exportMarkdown(language: languageManager.currentLanguage).data(using: .utf8) {
                try? data.write(to: url)
            }
        }
    }
    
    private func exportToCSV() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.commaSeparatedText]
        savePanel.nameFieldStringValue = "Cavi_iCollegamenti.csv"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let data = historyStore.exportCSV().data(using: .utf8) {
                try? data.write(to: url)
            }
        }
    }
    
    private func exportToJSON() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType.json]
        savePanel.nameFieldStringValue = "Cavi_iCollegamenti.json"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            if let data = historyStore.exportJSON().data(using: .utf8) {
                try? data.write(to: url)
            }
        }
    }
}
