import SwiftUI
import CAVICore

public struct GuidedCableWizardView: View {
    @Environment(DeviceDiscoveryService.self) private var discoveryService
    @Environment(TestHistoryStore.self) private var historyStore
    @Environment(BenchmarkService.self) private var benchmarkService
    @Environment(MacChargingService.self) private var macCharging
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(LanguageManager.self) private var languageManager
    
    @State private var currentStep = 1
    @State private var cableName = ""
    @State private var selectedCableID: UUID?
    @State private var testNotes = ""
    @State private var isCompleted = false
    @State private var savedResultID: UUID?
    @State private var wizardBenchmarkResult: BenchmarkResult?
    @State private var wizardBenchmarkError: String?
    @State private var forceReRun = false
    @State private var diagnosticMode: GuidedDiagnosticMode = .driveIsSlow
    
    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            wizardHeader
            
            if let device = discoveryService.selectedDevice,
               let existingSaved = historyStore.savedResult(forConnection: discoveryService.connectionFingerprint(for: device)),
               !forceReRun {
                savedDeviceOverviewCard(device: device, saved: existingSaved)
            } else {
                switch currentStep {
                case 1: step1DeviceSelection
                case 2: step2PowerDelivery
                case 3: step3PerformanceTest
                case 4: step4CertificateSummary
                default: EmptyView()
                }
                
                Spacer()
                
                wizardFooter
            }
        }
        .padding()
        .onAppear {
            if discoveryService.selectedDevice == nil {
                discoveryService.selectedDevice = discoveryService.devices.first(where: \.isStorageDevice) ?? discoveryService.devices.first
            }
            populateFromSavedIfAvailable()
        }
        .onChange(of: discoveryService.devices) { _, newDevices in
            if discoveryService.selectedDevice == nil {
                discoveryService.selectedDevice = newDevices.first(where: \.isStorageDevice) ?? newDevices.first
            }
        }
        .onChange(of: discoveryService.selectedDevice?.bsdName) { _, _ in
            forceReRun = false
            populateFromSavedIfAvailable()
        }
    }
    
    // MARK: - Header & Step Indicator
    
    private var wizardHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(languageManager.t("Guided Wizard", "Diagnosi guidata"))
                    .font(.title2.weight(.bold))
                Text(languageManager.t(
                    modeSubtitle,
                    modeSubtitleItalian
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            
            HStack(alignment: .center, spacing: 6) {
                stepBadge(number: 1, title: stepTitle(1), active: currentStep == 1, done: currentStep > 1)
                stepConnector
                stepBadge(number: 2, title: stepTitle(2), active: currentStep == 2, done: currentStep > 2)
                stepConnector
                stepBadge(number: 3, title: stepTitle(3), active: currentStep == 3, done: currentStep > 3)
                stepConnector
                stepBadge(number: 4, title: stepTitle(4), active: currentStep == 4, done: isCompleted)
            }
        }
    }

    private func stepTitle(_ number: Int) -> String {
        switch diagnosticMode {
        case .driveIsSlow:
            switch number {
            case 1: return languageManager.t("Device", "Dispositivo")
            case 2: return languageManager.t("Chain", "Catena")
            case 3: return languageManager.t("Benchmark", "Benchmark")
            default: return languageManager.t("Diagnosis", "Diagnosi")
            }
        case .cableIsGood:
            switch number {
            case 1: return languageManager.t("Protocol", "Protocollo")
            case 2: return languageManager.t("Power", "Potenza")
            case 3: return languageManager.t("Stability", "Stabilità")
            default: return languageManager.t("Rating", "Valutazione")
            }
        case .ssdIsHealthy:
            switch number {
            case 1: return languageManager.t("SMART", "SMART")
            case 2: return languageManager.t("Health", "Salute")
            case 3: return languageManager.t("Performance", "Prestazioni")
            default: return languageManager.t("Report", "Report")
            }
        case .dockOrHub:
            switch number {
            case 1: return languageManager.t("Topology", "Topologia")
            case 2: return languageManager.t("Bandwidth", "Banda")
            case 3: return languageManager.t("Ports", "Porte")
            default: return languageManager.t("Assessment", "Valutazione")
            }
        }
    }

    private var diagnosticModePicker: some View {
        Picker(languageManager.t("Diagnostic goal", "Obiettivo diagnosi"), selection: $diagnosticMode) {
            ForEach(GuidedDiagnosticMode.allCases) { mode in
                Text(modeTitle(mode)).tag(mode)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 290, alignment: .trailing)
    }
    
    private func stepBadge(number: Int, title: String, active: Bool, done: Bool) -> some View {
        VStack(alignment: .center, spacing: 4) {
            ZStack(alignment: .center) {
                Circle()
                    .fill(done ? Color.green : (active ? Color.accentColor : Color.secondary.opacity(0.2)))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(active ? .white : .secondary)
                }
            }
            Text(title)
                .font(.caption2.weight(active ? .bold : .regular))
                .foregroundStyle(active ? .primary : .secondary)
        }
    }
    
    private var stepConnector: some View {
        VStack {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 14, height: 2)
        }
        .frame(height: 28, alignment: .center)
    }
    
    // MARK: - Step 1: Device Selection & Link Detection
    
    private var step1DeviceSelection: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox(languageManager.t("Diagnostic Goal", "Obiettivo della diagnosi")) {
                    VStack(alignment: .leading, spacing: 8) {
                        diagnosticModePicker
                        Text(modeChecklist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                GroupBox(languageManager.t("Step 1: Select Device", "Passo 1: Seleziona il dispositivo")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(languageManager.t(
                            "Choose the connected peripheral, storage card, or display you wish to test:",
                            "Scegli la periferica, la scheda di archiviazione o il monitor che desideri testare:"
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        
                        if discoveryService.devices.isEmpty {
                            ContentUnavailableView(
                                languageManager.t("No USB devices detected", "Nessun dispositivo USB rilevato"),
                                systemImage: "cable.connector.exclamationmark",
                                description: Text(languageManager.t("Connect a USB or Thunderbolt device and refresh the list.", "Collega un dispositivo USB o Thunderbolt e aggiorna l’elenco."))
                            )
                        } else {
                            @Bindable var discovery = discoveryService
                            Picker(languageManager.t("Device under test", "Dispositivo sotto test"), selection: $discovery.selectedDevice) {
                                ForEach(discoveryService.devices) { dev in
                                    Text("\(dev.displayName) (\(dev.negotiatedSpeedFormatted))").tag(Optional(dev))
                                }
                            }
                            .pickerStyle(.menu)
                            
                            if let device = discoveryService.selectedDevice {
                                Divider()
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        if device.storageConnectionKind == .integratedSDReader {
                                            Text(device.connectionDescription(using: languageManager))
                                                .font(.title3.weight(.bold))
                                            Text(languageManager.t(
                                                "No USB cable is part of this test.",
                                                "Nessun cavo USB fa parte di questo test."
                                            ))
                                        } else {
                                            Text("\(languageManager.t("Negotiated Speed", "Velocità negoziata")): \(device.negotiatedSpeedFormatted)")
                                                .font(.title3.weight(.bold))
                                            Text(device.speedRating.protocolDescription)
                                        }
                                    }
                                    Spacer()
                                    if device.storageConnectionKind.supportsUSBTopology {
                                        Text(device.speedRating.label)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                if device.storageConnectionKind.supportsUSBTopology {
                                    Text(device.speedRating.detailedDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    preliminaryDiagnosisCard(for: device)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func preliminaryDiagnosisCard(for device: DriveDevice) -> some View {
        let diagnosis = ConnectionDiagnosisEngine.analyze(
            currentLinkSpeedBps: device.negotiatedSpeedBps,
            referenceMaxSpeedBps: historyStore.findReferenceDevice(for: device)?.maxObservedSpeedBps,
            constraints: USBTopologyService.connectionConstraints(for: device.usbTopology)
        )

        return VStack(alignment: .leading, spacing: 8) {
            Text(languageManager.t("Why might this drive be slow?", "Perché questo drive potrebbe essere lento?"))
                .font(.headline)

            SemanticStatus(
                wizardDiagnosisTitle(diagnosis),
                systemImage: wizardDiagnosisIcon(diagnosis),
                tone: wizardDiagnosisTone(diagnosis)
            )

            Text(wizardDiagnosisMessage(diagnosis))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(wizardDiagnosisNextCheck(diagnosis))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
    }

    private func wizardDiagnosisTitle(_ diagnosis: ConnectionDiagnosis) -> String {
        switch diagnosis.primaryCause {
        case .hub:
            return languageManager.t("Observed hub limitation", "Limitazione dell’hub osservata")
        case .connectionChain:
            return languageManager.t("Possible connection-chain limitation", "Possibile limitazione nella catena")
        case .unknown:
            return languageManager.t("Link speed unavailable", "Velocità del link non disponibile")
        case .none:
            return languageManager.t("Observed link recorded", "Link osservato registrato")
        case .bridge:
            return languageManager.t("Bridge controller limitation", "Limitazione del controller bridge")
        case .cable, .port:
            return languageManager.t("Cable limitation", "Limitazione del cavo")
        case .device:
            return languageManager.t("Device limitation", "Limitazione del dispositivo")
        }
    }

    private func wizardDiagnosisMessage(_ diagnosis: ConnectionDiagnosis) -> String {
        let current = diagnosis.currentLinkSpeedBps.map(LinkSpeedService.formatSpeed)
            ?? languageManager.t("not available", "non disponibile")
        let reference = diagnosis.referenceMaxSpeedBps.map(LinkSpeedService.formatSpeed)

        switch diagnosis.primaryCause {
        case .hub:
            return languageManager.t(
                "An observed hub link matches the current \(current) speed; this drive was previously measured at \(reference ?? languageManager.t("not available", "non disponibile")).",
                "Un link dell’hub osservato coincide con la velocità attuale di \(current); questo drive è stato misurato in precedenza a \(reference ?? languageManager.t("non disponibile", "non disponibile"))."
            )
        case .connectionChain:
            return languageManager.t(
                "This drive was previously measured at \(reference ?? languageManager.t("not available", "non disponibile")), but the current link is \(current).",
                "Questo drive è stato misurato in precedenza a \(reference ?? languageManager.t("non disponibile", "non disponibile")), ma il link attuale è \(current)."
            )
        case .unknown:
            return languageManager.t(
                "macOS did not expose a negotiated link speed for this connection.",
                "macOS non ha esposto una velocità di link negoziata per questa connessione."
            )
        case .none:
            return languageManager.t(
                "The observed negotiated link is \(current). No faster reference is available for comparison.",
                "Il link negoziato osservato è \(current). Non è disponibile un riferimento più veloce per il confronto."
            )
        case .bridge:
            return languageManager.t(
                "The USB-NVMe bridge controller supports up to \(current), limiting the connection.",
                "Il controller bridge USB-NVMe supporta fino a \(current), limitando la connessione."
            )
        case .cable, .port:
            return languageManager.t(
                "The cable or port is likely limiting the connection to \(current).",
                "Il cavo o la porta sta probabilmente limitando la connessione a \(current)."
            )
        case .device:
            return languageManager.t(
                "The SSD/device itself is the performance-limiting component.",
                "L'SSD/dispositivo stesso è il componente che limita le prestazioni."
            )
        }
    }

    private func wizardDiagnosisNextCheck(_ diagnosis: ConnectionDiagnosis) -> String {
        switch diagnosis.primaryCause {
        case .hub:
            return languageManager.t(
                "Safe next check: compare with a direct port or another observed hub link.",
                "Controllo sicuro successivo: confronta con una porta diretta o con un altro link dell’hub osservato."
            )
        case .connectionChain:
            return languageManager.t(
                "Safe next check: repeat the comparison by changing only one of cable, port, adapter, or hub.",
                "Controllo sicuro successivo: ripeti il confronto cambiando solo cavo, porta, adattatore o hub."
            )
        case .unknown:
            return languageManager.t(
                "Safe next check: reconnect the device and refresh the connection inventory.",
                "Controllo sicuro successivo: ricollega il dispositivo e aggiorna l’inventario dei collegamenti."
            )
        case .none:
            return languageManager.t(
                "Safe next check: save this device as a reference after a known-good direct connection.",
                "Controllo sicuro successivo: salva questo dispositivo come riferimento dopo un collegamento diretto noto come valido."
            )
        case .bridge:
            return languageManager.t(
                "Safe next check: check device documentation for controller limits.",
                "Controllo sicuro successivo: verifica la documentazione del dispositivo per i limiti del controller."
            )
        case .cable, .port:
            return languageManager.t(
                "Safe next check: repeat the comparison with a different cable or port.",
                "Controllo sicuro successivo: ripeti il confronto con un cavo o porta diversa."
            )
        case .device:
            return languageManager.t(
                "Safe next check: no action needed, device is operating at its maximum.",
                "Controllo sicuro successivo: nessuna azione necessaria, il dispositivo sta operando al suo massimo."
            )
        }
    }

    private func wizardDiagnosisIcon(_ diagnosis: ConnectionDiagnosis) -> String {
        switch diagnosis.warningLevel {
        case .critical: "exclamationmark.triangle.fill"
        case .attention: "exclamationmark.circle.fill"
        case .info: "checkmark.circle.fill"
        }
    }

    private func wizardDiagnosisTone(_ diagnosis: ConnectionDiagnosis) -> SemanticStatusTone {
        switch diagnosis.warningLevel {
        case .critical: .error
        case .attention: .warning
        case .info: .success
        }
    }
    
    // MARK: - Step 2: Power Delivery Analysis
    
    private var step2PowerDelivery: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox(languageManager.t("Step 2: Power Delivery", "Passo 2: Alimentazione")) {
                    VStack(alignment: .leading, spacing: 14) {
                        if let device = discoveryService.selectedDevice {
                            LabeledContent(languageManager.t("Device", "Dispositivo"), value: device.displayName)
                            LabeledContent(languageManager.t("Observed Port Intake", "Assorbimento rilevato porta"), value: device.chargingAssessment.title)
                            Text(device.chargingAssessment.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        
                        Text(languageManager.t("Mac Charging Status", "Stato Ricarica Mac"))
                            .font(.headline)
                        LabeledContent(
                            languageManager.t("Connected Power Adapter", "Alimentatore collegato"),
                            value: macCharging.snapshot.adapterWatts.map { "\($0) W" } ?? languageManager.t("None", "Nessuno")
                        )
                        LabeledContent(languageManager.t("Battery State", "Stato Batteria"), value: macCharging.snapshot.batteryState)
                        if let percentage = macCharging.snapshot.batteryPercent {
                            LabeledContent(languageManager.t("Battery Percentage", "Percentuale Batteria"), value: "\(percentage)%")
                        }
                        
                        SemanticStatus(
                            macCharging.snapshot.assessment,
                            systemImage: macCharging.snapshot.isOnExternalPower ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            tone: macCharging.snapshot.isOnExternalPower ? .success : .warning
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Step 3: Performance & Stability
    
    private var step3PerformanceTest: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox(languageManager.t("Step 3: Speed & Stability", "Passo 3: Velocità e stabilità")) {
                    VStack(alignment: .leading, spacing: 14) {
                        if let device = discoveryService.selectedDevice {
                            if diagnosticMode.requiresStorage, !device.isStorageDevice {
                                SemanticStatus(
                                    languageManager.t("This diagnostic needs a mounted storage drive.", "Questa diagnosi richiede un’unità di archiviazione montata."),
                                    systemImage: "externaldrive.badge.questionmark",
                                    tone: .warning
                                )
                            }
                            if device.isStorageDevice {
                                Text(languageManager.t(
                                    "The device is a storage drive (\(device.displayName)). You can run a quick benchmark test:",
                                    "Il dispositivo è un'unità di memoria (\(device.displayName)). È possibile eseguire un rapido benchmark di trasferimento dati:"
                                ))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                BenchmarkLinkExpectationView(linkSpeedBps: device.negotiatedSpeedBps)
                                
                                if !device.isMounted || device.mountPath.isEmpty {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(languageManager.t("Volume not mounted", "Volume non montato")) (\(device.bsdName))")
                                                .font(.headline)
                                            Text(languageManager.t(
                                                "Mount the disk volume to run read and write benchmark tests.",
                                                "Monta il volume del disco per poter eseguire il test di lettura e scrittura."
                                            ))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button(languageManager.t("Mount Volume", "Monta volume")) {
                                            Task { @MainActor in
                                                do {
                                                    try await discoveryService.mountDevice(device)
                                                    wizardBenchmarkError = nil
                                                } catch {
                                                    wizardBenchmarkError = error.localizedDescription
                                                }
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                    }
                                    .padding(.vertical, 4)
                                } else if benchmarkService.isRunning {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text(benchmarkService.currentPhase)
                                                .font(.headline)
                                            Spacer()
                                            Button(languageManager.t("Cancel", "Annulla"), role: .cancel) {
                                                benchmarkService.cancel()
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                        ProgressView(value: benchmarkService.progress)
                                        Text("\(Int((benchmarkService.progress * 100).rounded()))% \(languageManager.t("completed — 256 MB temporary test file.", "completato — test temporaneo 256 MB."))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                } else if let res = wizardBenchmarkResult {
                                    VStack(alignment: .leading, spacing: 10) {
                                        SemanticStatus(languageManager.t("Benchmark completed", "Benchmark completato"), systemImage: "checkmark.circle.fill", tone: .success)
                                        
                                        HStack(spacing: 32) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(languageManager.t("Write", "Scrittura")).font(.caption).foregroundStyle(.secondary)
                                                Text(String(format: "%.1f MB/s", res.sequentialWriteMBps))
                                                    .font(.title2.weight(.bold))
                                                    .monospacedDigit()
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(languageManager.t("Read", "Lettura")).font(.caption).foregroundStyle(.secondary)
                                                Text(String(format: "%.1f MB/s", res.sequentialReadMBps))
                                                    .font(.title2.weight(.bold))
                                                    .monospacedDigit()
                                            }
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(languageManager.t("Duration", "Durata")).font(.caption).foregroundStyle(.secondary)
                                                Text(String(format: "%.1f s", res.durationSeconds))
                                                    .font(.title2.weight(.semibold))
                                            }
                                        }
                                        
                                        Button(languageManager.t("Repeat Test (256 MB)", "Ripeti test (256 MB)")) {
                                            runWizardBenchmark(for: device)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    .padding(.vertical, 4)
                                } else {
                                    Button(languageManager.t("Run Read/Write Benchmark (256 MB)", "Esegui test di lettura/scrittura (256 MB)")) {
                                        runWizardBenchmark(for: device)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                
                                if let err = wizardBenchmarkError {
                                    SemanticStatus("\(languageManager.t("Test error:", "Errore test:")) \(err)", systemImage: "exclamationmark.triangle.fill", tone: .error)
                                }
                            } else {
                                Text("\(languageManager.t("The peripheral", "La periferica")) (\(device.displayName)) \(languageManager.t("is a system USB device (non-storage). Hardware negotiated link speed is", "è un dispositivo USB di sistema (non-storage). La velocità del link hardware negoziata è pari a")) **\(device.negotiatedSpeedFormatted)**.")
                                    .font(.subheadline)
                            }
                            
                            Divider()
                            
                            if device.storageConnectionKind.supportsUSBTopology,
                               let bottleneck = USBTopologyService.findBottleneck(in: device.usbTopology) {
                                SemanticStatus("\(languageManager.t("Bottleneck detected:", "Collo di bottiglia rilevato:")) \(bottleneck.message)", systemImage: "exclamationmark.triangle.fill", tone: .warning)
                            } else if !device.storageConnectionKind.supportsUSBTopology {
                                SemanticStatus(languageManager.t("No USB cable is part of this test.", "Nessun cavo USB fa parte di questo test."), systemImage: "info.circle", tone: .neutral)
                            } else {
                                SemanticStatus(languageManager.t("No hub bottlenecks detected in topology", "Nessun collo di bottiglia hub rilevato nella topologia"), systemImage: "checkmark.circle.fill", tone: .success)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func runWizardBenchmark(for device: DriveDevice) {
        wizardBenchmarkError = nil
        Task {
            do {
                let completed = try await benchmarkService.runBenchmark(mountPath: device.mountPath, config: BenchmarkConfig(testSizeBytes: 256_000_000))
                wizardBenchmarkResult = completed
                
                let fingerprint = discoveryService.connectionFingerprint(for: device)
                let resID = historyStore.upsertAutomaticResult(for: device, fingerprint: fingerprint)
                historyStore.attachBenchmark(completed, to: resID)
                if !cableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    historyStore.renameTestResult(id: resID, newLabel: cableName.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                savedResultID = resID
            } catch {
                wizardBenchmarkError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func modeTitle(_ mode: GuidedDiagnosticMode) -> String {
        switch mode {
        case .driveIsSlow: languageManager.t("Why is my drive slow?", "Perché il drive è lento?")
        case .cableIsGood: languageManager.t("Is this cable good?", "Il cavo è adeguato?")
        case .ssdIsHealthy: languageManager.t("Is this SSD healthy?", "L’SSD è in salute?")
        case .dockOrHub: languageManager.t("Check dock or hub", "Controlla dock o hub")
        }
    }

    private var modeSubtitle: String {
        switch diagnosticMode {
        case .driveIsSlow: "Four steps to identify the observed link, topology, benchmark, and likely causes of slow drive performance."
        case .cableIsGood: "Four steps to check observed data link, available power information, stability, and optional benchmark evidence."
        case .ssdIsHealthy: "Four steps to check the storage link, available drive health, benchmark behavior, and data integrity evidence."
        case .dockOrHub: "Four steps to inspect the observed uplink, shared bandwidth, available power information, and connected devices."
        }
    }

    private var modeSubtitleItalian: String {
        switch diagnosticMode {
        case .driveIsSlow: "Quattro passaggi per identificare link osservato, topologia, benchmark e cause probabili della lentezza del drive."
        case .cableIsGood: "Quattro passaggi per controllare link dati osservato, informazioni di potenza disponibili, stabilità e benchmark opzionale."
        case .ssdIsHealthy: "Quattro passaggi per controllare link storage, salute unità disponibile, comportamento del benchmark e integrità dati."
        case .dockOrHub: "Quattro passaggi per ispezionare uplink osservato, banda condivisa, potenza disponibile e dispositivi collegati."
        }
    }

    private var modeChecklist: String {
        let checklist: String
        switch diagnosticMode {
        case .driveIsSlow:
            checklist = languageManager.t("Checks: negotiated link, chain, quick benchmark, and observed warnings.", "Controlli: link negoziato, catena, benchmark rapido e warning osservati.")
        case .cableIsGood:
            checklist = languageManager.t("Checks: observed link and stability. Cable certification and e-marker are shown only when macOS exposes them.", "Controlli: link e stabilità osservati. Certificazione cavo ed e-marker sono mostrati solo se macOS li espone.")
        case .ssdIsHealthy:
            checklist = languageManager.t("Checks: available SMART data, temperature, wear, quick benchmark, and integrity test when you choose it.", "Controlli: dati SMART disponibili, temperatura, usura, benchmark rapido e test d’integrità quando lo scegli.")
        case .dockOrHub:
            checklist = languageManager.t("Checks: observed topology, uplink budget, connected consumers, and available power information.", "Controlli: topologia osservata, budget uplink, consumer collegati e informazioni di potenza disponibili.")
        }
        return checklist
    }
    
    // MARK: - Step 4: Summary
    
    private var step4CertificateSummary: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let device = discoveryService.selectedDevice {
                    let isIntegratedSD = device.storageConnectionKind == .integratedSDReader
                    let isDirect = isIntegratedSD || !device.usbTopology.contains(where: { $0.isHub })
                    let autoName = defaultLabel(for: device)
                    
                    GroupBox(isIntegratedSD
                             ? languageManager.t("Integrated SD Card Summary", "Riepilogo scheda SD integrata")
                             : isDirect 
                             ? languageManager.t("Device Summary", "Riepilogo del dispositivo") 
                             : languageManager.t("Connection Summary", "Riepilogo del collegamento")) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(languageManager.t("Summary", "Riepilogo"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(isIntegratedSD ? device.connectionDescription(using: languageManager) : device.speedRating.protocolDescription)
                                        .font(.title2.weight(.bold))
                                }
                                Spacer()
                                if !isIntegratedSD {
                                    Text(device.speedRating.label)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 6) {
                                LabeledContent(languageManager.t("Tested Device", "Dispositivo testato"), value: device.displayName)
                                LabeledContent(
                                    languageManager.t("Connection Type", "Tipo collegamento"),
                                    value: isIntegratedSD
                                        ? device.connectionDescription(using: languageManager)
                                        : isDirect 
                                        ? languageManager.t("Direct (integrated cable or flash drive)", "Diretta (dispositivo senza cavo esteso)") 
                                        : languageManager.t("Via Cable / Hub", "Tramite cavo/hub")
                                )
                                if device.storageConnectionKind.supportsUSBTopology {
                                    LabeledContent(languageManager.t("Link Speed", "Velocità link"), value: device.negotiatedSpeedFormatted)
                                }
                                if let res = wizardBenchmarkResult {
                                    LabeledContent(languageManager.t("Measured Write Speed", "Velocità Scrittura misurata"), value: String(format: "%.1f MB/s", res.sequentialWriteMBps))
                                    LabeledContent(languageManager.t("Measured Read Speed", "Velocità Lettura misurata"), value: String(format: "%.1f MB/s", res.sequentialReadMBps))
                                }
                                if device.storageConnectionKind.supportsUSBTopology {
                                    LabeledContent(languageManager.t("USB Topology", "Topologia USB"), value: USBTopologyService.topologyDescription(for: device))
                                } else {
                                    Text(languageManager.t(
                                        "The test concerns the card and integrated reader, not a cable.",
                                        "Il test riguarda la scheda e il lettore integrato, non un cavo."
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(isDirect 
                                     ? languageManager.t("Device / Connection Label", "Etichetta dispositivo / collegamento") 
                                     : languageManager.t("Cable Name / Label", "Nome del cavo / Etichetta"))
                                    .font(.subheadline.weight(.medium))

                                if device.storageConnectionKind.supportsUSBTopology {
                                    CableCatalogSelection(
                                        selectedCableID: $selectedCableID,
                                        cableName: $cableName,
                                        prompt: languageManager.t("Cable name (e.g. Anker USB-C 10Gbps)", "Nome del cavo (es. Anker USB-C 10Gbps)")
                                    )
                                } else {
                                    TextField(languageManager.t("Card label", "Etichetta scheda"), text: $cableName)
                                        .textFieldStyle(.roundedBorder)
                                }

                                Button("\(languageManager.t("Use", "Usa")) \"\(autoName)\"") {
                                    cableName = autoName
                                }
                                .buttonStyle(.bordered)
                                
                                Text(languageManager.t("Personal notes (optional)", "Note personali (opzionale)"))
                                    .font(.subheadline.weight(.medium))
                                TextField(isDirect 
                                          ? languageManager.t("e.g. Connected directly to Mac USB port", "Es. Collegato direttamente alla porta USB Mac") 
                                          : languageManager.t("e.g. Purchased in 2025, used for NVMe SSD", "Es. Acquistato nel 2025, usato per SSD NVMe"), text: $testNotes)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Button(action: saveWizardResult) {
                                Label(
                                    savedResultID != nil 
                                        ? languageManager.t("Result Saved", "Risultato salvato") 
                                        : languageManager.t("Save to History", "Salva nella cronologia"),
                                    systemImage: "square.and.arrow.down.fill"
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(cableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .onAppear {
                        if cableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            cableName = autoName
                        }
                    }
                }
            }
        }
    }
    
    private func defaultLabel(for device: DriveDevice) -> String {
        if device.storageConnectionKind == .integratedSDReader {
            return "\(device.displayName) — \(languageManager.t("Integrated SD reader", "Lettore SD integrato"))"
        }
        let isDirect = !device.usbTopology.contains(where: { $0.isHub })
        let directLabel = languageManager.t("Direct", "Diretto")
        let connLabel = languageManager.t("Connection", "Collegamento")
        return isDirect ? "\(device.displayName) (\(directLabel))" : "\(connLabel) \(device.displayName)"
    }
    
    // MARK: - Footer Controls
    
    private var wizardFooter: some View {
        HStack {
            if currentStep > 1 {
                Button(languageManager.t("Previous", "Precedente")) {
                    currentStep -= 1
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            if currentStep < 4 {
                Button(languageManager.t("Next", "Avanti")) {
                    currentStep += 1
                }
                .buttonStyle(.borderedProminent)
                .disabled(discoveryService.selectedDevice == nil)
            } else {
                Button(languageManager.t("Complete Wizard", "Completa Wizard")) {
                    isCompleted = true
                    currentStep = 1
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private func saveWizardResult() {
        guard let device = discoveryService.selectedDevice else { return }
        let cable: CableProfile?
        let name: String
        if device.storageConnectionKind.supportsUSBTopology {
            guard let resolvedCable = resolvedCableProfile() else { return }
            cable = resolvedCable
            name = resolvedCable.name
            historyStore.confirmCable(resolvedCable.id, forConnection: discoveryService.connectionFingerprint(for: device))
        } else {
            let label = cableName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return }
            cable = nil
            name = label
        }

        if let savedResultID {
            historyStore.renameTestResult(id: savedResultID, newLabel: name)
            historyStore.assignCable(cable?.id, toResult: savedResultID)
            historyStore.updateNotes(id: savedResultID, notes: testNotes)
            return
        }
        
        let result = CableTestResult(
            cableLabel: name,
            deviceName: device.displayName,
            deviceVendorID: device.vendorID,
            deviceProductID: device.productID,
            deviceSerialNumber: device.serialNumber,
            linkSpeedBps: device.negotiatedSpeedBps ?? 0,
            benchmarkReadMBps: wizardBenchmarkResult?.sequentialReadMBps,
            benchmarkWriteMBps: wizardBenchmarkResult?.sequentialWriteMBps,
            userNotes: testNotes,
            topologyDescription: device.storageConnectionKind.supportsUSBTopology
                ? USBTopologyService.topologyDescription(for: device)
                : device.storageConnectionKind.connectionDescription,
            connectionFingerprint: discoveryService.connectionFingerprint(for: device),
            cableID: cable?.id,
            category: .data
        )
        historyStore.saveTestResult(result)
        savedResultID = result.id
    }
    
    private func populateFromSavedIfAvailable() {
        guard let device = discoveryService.selectedDevice,
              let saved = historyStore.savedResult(forConnection: discoveryService.connectionFingerprint(for: device)) else { return }
        
        cableName = saved.cableLabel
        selectedCableID = saved.cableID
        testNotes = saved.userNotes ?? ""
        savedResultID = saved.id
        if let read = saved.benchmarkReadMBps, let write = saved.benchmarkWriteMBps {
            wizardBenchmarkResult = BenchmarkResult(
                sequentialReadMBps: read,
                sequentialWriteMBps: write,
                testSizeBytes: 256_000_000,
                timestamp: saved.timestamp,
                durationSeconds: 0
            )
        }
    }

    private func resolvedCableProfile() -> CableProfile? {
        let name = cableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let selectedCableID, let existing = historyStore.cableProfile(id: selectedCableID) {
            historyStore.renameCable(id: existing.id, newName: name)
            return historyStore.cableProfile(id: existing.id) ?? existing
        }
        let cable = historyStore.createCable(named: name)
        selectedCableID = cable.id
        return cable
    }
    
    private func savedDeviceOverviewCard(device: DriveDevice, saved: CableTestResult) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox(languageManager.t("Previously Saved Result", "Risultato già salvato")) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(languageManager.t(
                                    "Saved result found for this connection:",
                                    "Risultato salvato in precedenza per questo collegamento:"
                                ))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                Text(saved.cableLabel)
                                    .font(.title2.weight(.bold))
                            }
                            Spacer()
                            Text(saved.rating.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Divider()
                        
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                            GridRow {
                                Text("\(languageManager.t("Device", "Dispositivo")):").foregroundStyle(.secondary)
                                Text(saved.deviceName).fontWeight(.medium)
                            }
                            GridRow {
                                Text("\(languageManager.t("Negotiated link speed", "Velocità link negoziata")):").foregroundStyle(.secondary)
                                Text(saved.linkSpeedFormatted).fontWeight(.medium)
                            }
                            if let read = saved.benchmarkReadMBps, let write = saved.benchmarkWriteMBps {
                                GridRow {
                                    Text("\(languageManager.t("Measured write speed", "Velocità Scrittura misurata")):").foregroundStyle(.secondary)
                                    Text(String(format: "%.1f MB/s", write)).monospacedDigit().fontWeight(.bold)
                                }
                                GridRow {
                                    Text("\(languageManager.t("Measured read speed", "Velocità Lettura misurata")):").foregroundStyle(.secondary)
                                    Text(String(format: "%.1f MB/s", read)).monospacedDigit().fontWeight(.bold)
                                }
                            }
                            if let topology = saved.topologyDescription, !topology.isEmpty {
                                GridRow {
                                    Text("\(device.storageConnectionKind.supportsUSBTopology ? languageManager.t("USB Topology", "Topologia USB") : languageManager.t("Connection", "Collegamento")):").foregroundStyle(.secondary)
                                    Text(topology)
                                }
                            }
                            if let notes = saved.userNotes, !notes.isEmpty {
                                GridRow {
                                    Text("\(languageManager.t("Saved notes", "Note salvate")):").foregroundStyle(.secondary)
                                    Text(notes)
                                }
                            }
                            GridRow {
                                Text("\(languageManager.t("Result date", "Data risultato")):").foregroundStyle(.secondary)
                                Text(saved.timestamp.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(languageManager.t("Update Label or Notes", "Aggiorna Etichetta o Note"))
                                .font(.headline)
                            TextField(
                                device.storageConnectionKind == .integratedSDReader
                                    ? languageManager.t("Card label", "Etichetta scheda")
                                    : languageManager.t("Cable label", "Etichetta cavo"),
                                text: $cableName
                            )
                                .textFieldStyle(.roundedBorder)
                            TextField(languageManager.t("Personal notes", "Note personali"), text: $testNotes)
                                .textFieldStyle(.roundedBorder)
                            Button(languageManager.t("Save Label Changes", "Salva modifiche etichetta")) {
                                saveWizardResult()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Divider()
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                forceReRun = true
                                currentStep = 1
                            }) {
                                Label(languageManager.t("Run Guided Wizard Again", "Ripeti la procedura guidata"), systemImage: "arrow.clockwise.circle")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }
}
