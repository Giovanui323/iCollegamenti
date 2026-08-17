import SwiftUI
import CAVICore

struct CableTesterMainView: View {
    @Environment(DeviceDiscoveryService.self) private var deviceDiscovery
    @Environment(TestHistoryStore.self) private var historyStore
    @Environment(BottleneckAnalyzerService.self) private var bottleneckAnalyzer
    @Environment(DiskIOMonitorService.self) private var ioMonitor
    @Environment(LanguageManager.self) private var languageManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var cableName: String = ""
    @State private var selectedCableID: UUID?
    @State private var showSavedConfirmation = false
    @State private var isEjecting = false
    @State private var ejectSuccessMessage: String?
    @State private var ejectErrorMessage: String?
    @State private var automaticResultID: UUID?
    @State private var suppressRegistrationUntilDisconnect = false
    @State private var connectionStartedAt = Date()
    
    var body: some View {
        Group {
            if let device = deviceDiscovery.selectedDevice {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        deviceSelector
                        if device.storageConnectionKind.supportsUSBTopology {
                            cableNameField
                        }
                        speedDisplay(for: device)
                        topologySection(for: device)
                        liveIOSection
                        analysisCard(for: device)
                        overallHardwareScoreSection(for: device)
                        actionButtons(for: device)
                    }
                    .padding()
                    .frame(maxWidth: 920, alignment: .leading)
                }
                .onAppear {
                    runAnalysis(for: device)
                    ioMonitor.startMonitoring(bsdName: device.bsdName)
                    promptForCableNameIfNeeded(device)
                }
                .onChange(of: deviceDiscovery.selectedDevice) { oldDevice, newDevice in
                    if let d = newDevice {
                        if oldDevice?.bsdName != d.bsdName { connectionStartedAt = Date() }
                        runAnalysis(for: d)
                        ioMonitor.startMonitoring(bsdName: d.bsdName)
                        if oldDevice?.bsdName != d.bsdName { promptForCableNameIfNeeded(d) }
                    } else {
                        suppressRegistrationUntilDisconnect = false
                        connectionStartedAt = Date()
                    }
                }
            } else {
                ContentUnavailableView(
                    languageManager.t("No USB Device Connected", "Nessun dispositivo USB"),
                    systemImage: "cable.connector",
                    description: Text(languageManager.t("Connect a device and refresh the list.", "Collega un dispositivo e aggiorna l’elenco."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert(languageManager.t("Unable to Eject", "Impossibile Espellere"), isPresented: Binding(
            get: { ejectErrorMessage != nil },
            set: { if !$0 { ejectErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { ejectErrorMessage = nil }
        } message: {
            Text(ejectErrorMessage ?? languageManager.t(
                "The device might be in use by another application (e.g. Finder or Terminal). Close open files on this drive and try again.",
                "Il dispositivo potrebbe essere in uso da un'altra applicazione (es. Finder o Terminale). Chiudi eventuali file aperti su questo disco e riprova."
            ))
        }
        .onAppear {
            if deviceDiscovery.selectedDevice == nil {
                deviceDiscovery.selectedDevice = deviceDiscovery.devices.first(where: \.isStorageDevice) ?? deviceDiscovery.devices.first
            }
        }
        .onChange(of: deviceDiscovery.devices) { _, newDevices in
            if deviceDiscovery.selectedDevice == nil {
                deviceDiscovery.selectedDevice = newDevices.first(where: \.isStorageDevice) ?? newDevices.first
            }
        }
    }
    
    // MARK: - Device Selector
    
    @MainActor
    private var deviceSelector: some View {
        HStack {
            Text(languageManager.t("Device:", "Dispositivo:"))
                .font(.headline)
            
            if deviceDiscovery.devices.isEmpty {
                Text(languageManager.t("No USB devices detected", "Nessun dispositivo USB rilevato"))
                    .foregroundStyle(.secondary)
            } else if deviceDiscovery.devices.count == 1 {
                Text(deviceDiscovery.devices.first?.displayName ?? "")
                    .fontWeight(.medium)
            } else {
                @Bindable var discovery = deviceDiscovery
                Picker("", selection: $discovery.selectedDevice) {
                    ForEach(deviceDiscovery.devices) { device in
                        HStack {
                            Image(systemName: device.isStorageDevice ? "externaldrive" : "cable.connector")
                            Text("\(device.displayName) (\(device.negotiatedSpeedFormatted))")
                        }
                        .tag(Optional(device))
                    }
                }
                .labelsHidden()
            }
            
            Spacer()
            
            if let device = deviceDiscovery.selectedDevice, device.isStorageDevice, !device.bsdName.isEmpty {
                Button(action: { eject(device: device) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "eject.fill")
                        Text(isEjecting 
                             ? languageManager.t("Ejecting...", "Espulsione...") 
                             : languageManager.t("Eject Device", "Espelli Dispositivo"))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isEjecting)
                .help(device.storageConnectionKind == .integratedSDReader
                    ? languageManager.t(
                        "Safely eject before removing the SD card.",
                        "Espelli in sicurezza prima di rimuovere la scheda SD."
                    )
                    : languageManager.t(
                        "Safely eject to swap cables without disk-in-use errors",
                        "Espelli in sicurezza per poter scollegare il cavo senza errori di disco in uso"
                    )
                )
            }
            
        }
    }
    
    // MARK: - Cable Identity
    
    private var cableNameField: some View {
        GroupBox(languageManager.t("Cable Identity", "Identità del cavo")) {
            VStack(alignment: .leading, spacing: 12) {
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

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        cableNameTextField
                        confirmCableButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        cableNameTextField
                        confirmCableButton
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                if let selectedCable = historyStore.cableProfile(id: selectedCableID) {
                    LabeledContent(languageManager.t("Unique code", "Codice univoco"), value: selectedCable.code)
                        .font(.caption)
                        .textSelection(.enabled)
                }

                if let suggestedCable, suggestedCable.id != selectedCableID {
                    HStack(spacing: 8) {
                        SemanticStatus(
                            languageManager.t("Possible registered cable", "Possibile cavo già registrato"),
                            systemImage: "questionmark.circle",
                            tone: .neutral
                        )
                        Button(languageManager.t("Use \(suggestedCable.code)", "Usa \(suggestedCable.code)")) {
                            confirmSuggestedCable(suggestedCable)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Text(languageManager.t(
                    "The code identifies this catalog entry. A match is only a suggestion until you confirm it.",
                    "Il codice identifica questa voce del catalogo. Un abbinamento è solo un suggerimento finché non lo confermi."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var cableNameTextField: some View {
        TextField(
            languageManager.t("Cable name (e.g. Anker USB-C 10Gbps)", "Nome del cavo (es. Anker USB-C 10Gbps)"),
            text: $cableName
        )
        .textFieldStyle(.roundedBorder)
        .font(.body)
        .onSubmit(confirmCableForCurrentConnection)
    }

    private var confirmCableButton: some View {
        Button(
            selectedCableID == nil
                ? languageManager.t("Register Cable", "Registra cavo")
                : languageManager.t("Confirm Association", "Conferma associazione"),
            systemImage: selectedCableID == nil ? "plus" : "checkmark"
        ) {
            confirmCableForCurrentConnection()
        }
        .buttonStyle(.borderedProminent)
        .disabled(cableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help(languageManager.t("Confirm the cable for this observed connection", "Conferma il cavo per questo collegamento osservato"))
    }
    
    // MARK: - Giant Speed Display
    
    private func speedDisplay(for device: DriveDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if device.storageConnectionKind == .integratedSDReader {
                LabeledContent(languageManager.t("Connection", "Collegamento"), value: device.connectionDescription(using: languageManager))
                Text(languageManager.t(
                    "Benchmark and transfer measurements apply to the card and integrated reader, not a cable.",
                    "Benchmark e trasferimenti misurano la scheda e il lettore integrato, non un cavo."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(languageManager.t("Negotiated Speed", "Velocità negoziata"))
                        .font(.headline)
                    Text(device.negotiatedSpeedFormatted)
                        .font(.title.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                LabeledContent(languageManager.t("USB Standard", "Standard USB"), value: device.speedRating.protocolDescription)
                powerObservation(for: device)
            }
        }
    }

    @ViewBuilder
    private func powerObservation(for device: DriveDevice) -> some View {
        if case let .observed(watts) = device.chargingAssessment {
            LabeledContent(languageManager.t("Power", "Alimentazione"), value: String(format: "%.1f W", watts))
        }
    }

    @ViewBuilder
    private func topologySection(for device: DriveDevice) -> some View {
        if device.storageConnectionKind.supportsUSBTopology, !device.usbTopology.isEmpty {
            GroupBox(languageManager.t("Connection Topology", "Topologia del collegamento")) {
                TopologyVisualizerView(
                    nodes: device.usbTopology,
                    hubBudgets: deviceDiscovery.bandwidthBudgets(for: device)
                )
            }
        }
    }
    
    // MARK: - Live I/O Monitor
    
    @ViewBuilder
    private var liveIOSection: some View {
        if let device = deviceDiscovery.selectedDevice, device.isStorageDevice {
            let fingerprint = recognitionFingerprint(for: device)
            let storedResult = historyStore.latestResult(forConnection: fingerprint)
            let writePeak = max(ioMonitor.maximumWriteMBps, storedResult?.benchmarkWriteMBps ?? 0)
            let readPeak = max(ioMonitor.maximumReadMBps, storedResult?.benchmarkReadMBps ?? 0)
            
            GroupBox(languageManager.t("Real-Time Transfer Speed", "Velocità di trasferimento in tempo reale")) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        if ioMonitor.isMonitoring {
                            SemanticStatus("Live", systemImage: "waveform.path.ecg", tone: .success)
                        }
                    }
                    HStack(spacing: 0) {
                        // Write speed
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(.secondary)
                                Text(languageManager.t("Write", "Scrittura"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(TransferSpeedFormatter.megabytesPerSecond(ioMonitor.currentWriteMBps))
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(ioMonitor.currentWriteMBps > 1 ? .primary : .secondary)
                            Text("\(languageManager.t("Peak:", "Picco:")) \(TransferSpeedFormatter.megabytesPerSecond(writePeak))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Divider()
                            .frame(height: 50)
                        
                        // Read speed
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundStyle(.secondary)
                                Text(languageManager.t("Read", "Lettura"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(TransferSpeedFormatter.megabytesPerSecond(ioMonitor.currentReadMBps))
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(ioMonitor.currentReadMBps > 1 ? .primary : .secondary)
                            Text("\(languageManager.t("Peak:", "Picco:")) \(TransferSpeedFormatter.megabytesPerSecond(readPeak))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    if storedResult?.benchmarkWriteMBps != nil || storedResult?.benchmarkReadMBps != nil {
                        Text(languageManager.t(
                            "Peak includes benchmarked and saved metrics for this connection.",
                            "Il picco include i dati misurati e salvati per questo collegamento."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(languageManager.t(
                            "Transfer a file or run a benchmark to measure actual read/write performance.",
                            "Trasferisci un file sul disco o esegui un benchmark per misurare la velocità effettiva."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Analysis Card
    
    @ViewBuilder
    private func analysisCard(for device: DriveDevice) -> some View {
        if let analysis = bottleneckAnalyzer.currentAnalysis {
            analysisView(analysis)
        } else {
            let reference = historyStore.findReferenceDevice(for: device)
            let assessment = LinkSpeedService.generateCableAssessment(
                currentSpeed: device.negotiatedSpeedBps,
                referenceMaxSpeed: reference?.maxObservedSpeedBps
            )
            assessmentView(assessment)
        }
    }
    
    private func analysisView(_ analysis: BottleneckAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SemanticStatus(
                analysisStatusTitle(for: analysis),
                systemImage: analysisIcon(for: analysis.severity),
                tone: analysisTone(for: analysis.severity)
            )

            Text(analysisMessage(for: analysis))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !analysis.possibleCauses.isEmpty {
                DisclosureGroup(languageManager.t("Possible Causes", "Possibili cause")) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(analysis.possibleCauses, id: \.self) { cause in
                            Text(cause)
                        }
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
            }

            DisclosureGroup(languageManager.t("Diagnostic Evidence", "Evidenze diagnostiche")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(analysis.diagnosis.evidences.enumerated()), id: \.offset) { _, evidence in
                        VStack(alignment: .leading, spacing: 2) {
                            LabeledContent(
                                evidence.label,
                                value: evidence.value ?? languageManager.t("Not available", "Non disponibile")
                            )
                            Text(evidenceSourceLabel(evidence.source))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func assessmentView(_ assessment: CableAssessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SemanticStatus(
                assessment.isBottleneck
                    ? languageManager.t("Possible connection limitation", "Possibile limitazione del collegamento")
                    : languageManager.t("No limitation detected", "Nessuna limitazione rilevata"),
                systemImage: assessment.isBottleneck ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                tone: assessment.isBottleneck ? .warning : .success
            )
            if let message = assessment.bottleneckMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Overall Hardware Score
    
    @ViewBuilder
    private func overallHardwareScoreSection(for device: DriveDevice) -> some View {
        let fingerprint = recognitionFingerprint(for: device)
        let storedResult = historyStore.latestResult(forConnection: fingerprint)
        let hasCable = selectedCableID != nil ? 90 : nil
        let components = HardwareScoreComponents(
            cable: hasCable,
            connection: bottleneckAnalyzer.currentAnalysis?.severity == .critical ? 40 : (bottleneckAnalyzer.currentAnalysis?.severity == .warning ? 70 : 100),
            performance: storedResult?.benchmarkReadMBps != nil ? 95 : nil,
            health: nil,
            power: nil,
            stability: nil
        )
        if let score = OverallHardwareScore.calculate(components) {
            GroupBox(languageManager.t("Overall Hardware Score", "Punteggio Hardware Globale")) {
                VStack(spacing: 16) {
                    HStack {
                        Text("\(score.value)/100")
                            .font(.system(size: 48, weight: .bold))
                        Spacer()
                        SemanticStatus(
                            levelLabel(for: score.level),
                            systemImage: levelIcon(for: score.level),
                            tone: levelTone(for: score.level)
                        )
                    }
                    
                    Text(languageManager.t("Based on \(score.includedComponentCount) measured components.", "Basato su \(score.includedComponentCount) componenti misurati."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        scoreBadge(title: languageManager.t("Cable", "Cavo"), value: components.cable)
                        scoreBadge(title: languageManager.t("Connection", "Connessione"), value: components.connection)
                        scoreBadge(title: languageManager.t("Performance", "Prestazioni"), value: components.performance)
                        scoreBadge(title: languageManager.t("Health", "Salute"), value: components.health)
                        scoreBadge(title: languageManager.t("Power", "Potenza"), value: components.power)
                        scoreBadge(title: languageManager.t("Stability", "Stabilità"), value: components.stability)
                    }
                }
            }
        }
    }
    
    private func levelLabel(for level: OverallHardwareScoreLevel) -> String {
        switch level {
        case .excellent: return languageManager.t("Excellent", "Eccellente")
        case .good: return languageManager.t("Good", "Buono")
        case .attention: return languageManager.t("Attention", "Attenzione")
        case .critical: return languageManager.t("Critical", "Critico")
        }
    }
    
    private func levelIcon(for level: OverallHardwareScoreLevel) -> String {
        switch level {
        case .excellent: return "star.fill"
        case .good: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
    
    private func levelTone(for level: OverallHardwareScoreLevel) -> SemanticStatusTone {
        switch level {
        case .excellent: return .success
        case .good: return .success
        case .attention: return .warning
        case .critical: return .error
        }
    }
    
    private func scoreBadge(title: String, value: Int?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let value = value {
                Text("\(value)")
                    .font(.headline)
            } else {
                Text("-")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Action Buttons
    
    private func actionButtons(for device: DriveDevice) -> some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    saveResultButton(for: device)
                    referenceDeviceButton(for: device)
                }

                VStack(alignment: .leading, spacing: 8) {
                    saveResultButton(for: device)
                    referenceDeviceButton(for: device)
                }
            }
            
            if showSavedConfirmation {
                SemanticStatus(languageManager.t("Result saved", "Risultato salvato"), systemImage: "checkmark.circle.fill", tone: .success)
                .transition(.opacity)
            }
        }
    }

    private func saveResultButton(for device: DriveDevice) -> some View {
        Button(languageManager.t("Save Result", "Salva risultato"), systemImage: "square.and.arrow.down") {
            saveCableResult(for: device)
        }
        .buttonStyle(.borderedProminent)
        .disabled(selectedCableID == nil)
    }

    private func referenceDeviceButton(for device: DriveDevice) -> some View {
        Button(languageManager.t("Reference Device", "Dispositivo di riferimento"), systemImage: "star") {
            let _ = historyStore.registerAsReference(device)
        }
        .buttonStyle(.bordered)
    }
    
    private func eject(device: DriveDevice) {
        isEjecting = true
        suppressRegistrationUntilDisconnect = true
        ioMonitor.stopMonitoring()
        Task {
            do {
                try await deviceDiscovery.ejectDevice(device)
                isEjecting = false
                ejectSuccessMessage = device.storageConnectionKind == .integratedSDReader
                    ? languageManager.t(
                        "SD card '\(device.displayName)' safely ejected. You can now remove the card.",
                        "Scheda SD '\(device.displayName)' espulsa in sicurezza. Ora puoi rimuovere la scheda."
                    )
                    : languageManager.t(
                        "Device '\(device.displayName)' safely ejected. You can now disconnect the cable!",
                        "Dispositivo '\(device.displayName)' espulso in sicurezza. Ora puoi cambiare il cavo!"
                    )
            } catch {
                isEjecting = false
                ejectErrorMessage = languageManager.t(
                    "Unable to eject '\(device.displayName)': \(error.localizedDescription)\n\nEnsure no files are open in Finder or Terminal on this disk.",
                    "Impossibile espellere '\(device.displayName)': \(error.localizedDescription)\n\nAssicurati che nessun file sia aperto nel Finder o nel Terminale su questo disco."
                )
            }
        }
    }

    private func promptForCableNameIfNeeded(_ device: DriveDevice) {
        guard !isEjecting, !suppressRegistrationUntilDisconnect else { return }
        let fingerprint = recognitionFingerprint(for: device)
        if let existing = historyStore.latestResult(forConnection: fingerprint) {
            automaticResultID = existing.id
            if let cable = historyStore.cableProfile(id: existing.cableID) {
                selectedCableID = cable.id
                cableName = cable.name
            } else {
                selectedCableID = nil
                cableName = ""
            }
            return
        }

        guard device.storageConnectionKind.supportsUSBTopology else {
            selectedCableID = nil
            cableName = ""
            automaticResultID = historyStore.upsertAutomaticResult(for: device, fingerprint: fingerprint)
            return
        }

        let isDirect = !device.usbTopology.contains(where: { $0.isHub })
        cableName = isDirect
            ? languageManager.t("Direct connection", "Collegamento diretto")
            : "\(device.speedRating.connectionType)"
        selectedCableID = nil
        automaticResultID = historyStore.upsertAutomaticResult(for: device, fingerprint: fingerprint)
    }
    
    private func runAnalysis(for device: DriveDevice) {
        let ref = historyStore.findReferenceDevice(for: device)
        let _ = bottleneckAnalyzer.analyze(device: device, referenceDevice: ref, language: languageManager.currentLanguage)
    }
    
    @discardableResult
    private func saveCableResult(for device: DriveDevice) -> UUID? {
        guard let cable = historyStore.cableProfile(id: selectedCableID) else { return nil }
        let result = CableTestResult(
            cableLabel: cable.name,
            deviceName: device.displayName,
            deviceVendorID: device.vendorID,
            deviceProductID: device.productID,
            deviceSerialNumber: device.serialNumber,
            linkSpeedBps: device.negotiatedSpeedBps ?? 0,
            topologyDescription: device.storageConnectionKind.supportsUSBTopology
                ? USBTopologyService.topologyDescription(for: device)
                : device.storageConnectionKind.connectionDescription,
            connectionFingerprint: recognitionFingerprint(for: device),
            cableID: cable.id
        )
        historyStore.saveTestResult(result)
        
        setSavedConfirmation(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            setSavedConfirmation(false)
        }
        return result.id
    }

    private func setSavedConfirmation(_ isPresented: Bool) {
        if reduceMotion {
            showSavedConfirmation = isPresented
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                showSavedConfirmation = isPresented
            }
        }
    }

    private func recognitionFingerprint(for device: DriveDevice) -> String {
        guard !device.bsdName.isEmpty else {
            return device.recognitionFingerprint(connectedAt: connectionStartedAt)
        }
        return deviceDiscovery.connectionFingerprint(for: device)
    }

    private var suggestedCable: CableProfile? {
        guard let device = deviceDiscovery.selectedDevice,
              device.storageConnectionKind.supportsUSBTopology else { return nil }
        return historyStore.suggestedCable(forConnection: recognitionFingerprint(for: device))
    }

    private func confirmSuggestedCable(_ cable: CableProfile) {
        selectedCableID = cable.id
        cableName = cable.name
        confirmCableForCurrentConnection()
    }

    private func confirmCableForCurrentConnection() {
        guard let device = deviceDiscovery.selectedDevice,
              device.storageConnectionKind.supportsUSBTopology else { return }
        let name = cableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let cable: CableProfile
        if let selectedCableID, let existing = historyStore.cableProfile(id: selectedCableID) {
            historyStore.renameCable(id: existing.id, newName: name)
            cable = historyStore.cableProfile(id: existing.id) ?? existing
        } else {
            cable = historyStore.createCable(named: name)
            selectedCableID = cable.id
        }

        let fingerprint = recognitionFingerprint(for: device)
        historyStore.confirmCable(cable.id, forConnection: fingerprint)
        if let automaticResultID {
            historyStore.renameTestResult(id: automaticResultID, newLabel: cable.name)
            historyStore.assignCable(cable.id, toResult: automaticResultID)
        }
        cableName = cable.name
    }
    
    private func analysisIcon(for severity: Severity) -> String {
        switch severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .none: return "checkmark.circle.fill"
        }
    }

    private func analysisTone(for severity: Severity) -> SemanticStatusTone {
        switch severity {
        case .critical: return .error
        case .warning: return .warning
        case .none: return .success
        }
    }

    private func analysisStatusTitle(for analysis: BottleneckAnalysis) -> String {
        switch analysis.diagnosis.primaryCause {
        case .hub:
            return languageManager.t("Observed hub limitation", "Limitazione dell’hub osservata")
        case .connectionChain:
            return languageManager.t("Possible connection-chain limitation", "Possibile limitazione nella catena")
        case .unknown:
            return languageManager.t("Link speed unavailable", "Velocità del link non disponibile")
        case .none:
            return languageManager.t("Connection consistent with available evidence", "Connessione coerente con le evidenze disponibili")
        case .bridge:
            return languageManager.t("Bridge controller limitation", "Limitazione del controller bridge")
        case .cable, .port:
            return languageManager.t("Cable limitation", "Limitazione del cavo")
        case .device:
            return languageManager.t("Device limitation", "Limitazione del dispositivo")
        }
    }

    private func analysisMessage(for analysis: BottleneckAnalysis) -> String {
        return analysis.detailedMessage
    }

    private func evidenceSourceLabel(_ source: EvidenceSource) -> String {
        switch source {
        case .ioRegistryObserved:
            languageManager.t("Observed from I/O Registry", "Osservato da I/O Registry")
        case .diskArbitrationObserved:
            languageManager.t("Observed from Disk Arbitration", "Osservato da Disk Arbitration")
        case .powerSourceObserved:
            languageManager.t("Observed from macOS power source", "Osservato dalla fonte di alimentazione macOS")
        case .benchmarkMeasured:
            languageManager.t("Measured benchmark reference", "Riferimento misurato con benchmark")
        case .catalogMatched:
            languageManager.t("Catalog match", "Abbinamento di catalogo")
        case .userConfirmed:
            languageManager.t("Confirmed by you", "Confermato dall’utente")
        case .inferred:
            languageManager.t("Inference, not directly observed", "Inferenza, non osservata direttamente")
        case .unavailable:
            languageManager.t("Not available", "Non disponibile")
        }
    }
}
