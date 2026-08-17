import SwiftUI
import CAVICore

struct USBFlashDriveTesterView: View {
    @Environment(DeviceDiscoveryService.self) private var discovery
    @Environment(BenchmarkService.self) private var benchmark
    @Environment(DriveHealthService.self) private var driveHealth
    @Environment(HardwareEventLog.self) private var hardwareEventLog
    @Environment(TestHistoryStore.self) private var historyStore
    @Environment(LanguageManager.self) private var languageManager
    @State private var result: BenchmarkResult?
    @State private var advancedResult: AdvancedBenchmarkResult?

    @State private var selectedTestBytes = AnalysisMetrics.compactBenchmarkBytes
    @State private var selectedAdvancedPreset: BenchmarkPreset = .standard1GiB
    @State private var selectedWorkload: BenchmarkWorkload = .sequential
    @State private var selectedRandomBlockSize: RandomBenchmarkBlockSize = .fourKiB
    @State private var stressDurationSeconds = 60
    @State private var confirmedExtendedPreset: BenchmarkPreset?
    @State private var showExtendedTestConfirmation = false
    @State private var isMounting = false
    @State private var mountErrorMessage: String?

    private var storageDevices: [DriveDevice] {
        discovery.devices.filter(\.isStorageDevice)
    }

    private var selectedStorageDeviceBinding: Binding<DriveDevice?> {
        Binding(
            get: {
                if let selected = discovery.selectedDevice,
                   let matching = storageDevices.first(where: {
                       $0.id == selected.id ||
                       ($0.physicalDeviceID != nil && $0.physicalDeviceID == selected.physicalDeviceID) ||
                       (!selected.bsdName.isEmpty && $0.bsdName == selected.bsdName)
                   }) {
                    return matching
                }
                return benchmarkDevice ?? storageDevices.first
            },
            set: { newValue in
                discovery.selectedDevice = newValue
            }
        )
    }

    private var benchmarkDevice: DriveDevice? {
        let candidates = storageDevices.map {
            StorageDeviceSelectionCandidate(id: $0.bsdName, isStorageDevice: $0.isStorageDevice, isMounted: $0.canRunBenchmark)
        }
        let selectedID = StorageDeviceSelectionPolicy.effectiveDeviceID(
            selected: discovery.selectedDevice?.bsdName,
            available: candidates
        )
        return storageDevices.first { $0.bsdName == selectedID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(languageManager.t(
                        "Sequential read and write measurements use a temporary file; existing files are never modified.",
                        "Le misurazioni sequenziali di lettura e scrittura usano un file temporaneo; i file esistenti non vengono modificati."
                    ))
                        .foregroundStyle(.secondary)
                        if !storageDevices.isEmpty {
                            Picker(languageManager.t("Drive to test", "Unità da testare"), selection: selectedStorageDeviceBinding) {
                                ForEach(storageDevices) { storageDevice in
                                    Text(storageDevice.displayName).tag(Optional(storageDevice))
                                }
                            }
                        }
                        if let device = benchmarkDevice {
                            if !device.isStorageDevice {
                                ContentUnavailableView(
                                    languageManager.t("Select a Storage Drive", "Seleziona un'unità di archiviazione"),
                                    systemImage: "externaldrive.badge.questionmark",
                                    description: Text(languageManager.t(
                                        "The benchmark requires a mountable USB storage volume; peripherals like hubs, keyboards, and mice cannot be benchmarked.",
                                        "Il benchmark richiede un volume USB montabile; periferiche come hub, tastiere e mouse non possono essere testate."
                                    ))
                                )
                                .frame(maxWidth: .infinity, minHeight: 220)
                            } else {
                                LabeledContent(languageManager.t("Selected drive", "Unità selezionata"), value: device.displayName)
                                LabeledContent(languageManager.t("Capacity", "Capacità"), value: device.capacityFormatted)
                                LabeledContent(languageManager.t("Connection", "Collegamento"), value: device.connectionDescription(using: languageManager))
                                driveHealthSummary(for: device)
                                connectionStabilitySummary(for: device)
                                if device.storageConnectionKind == .integratedSDReader {
                                    Text(languageManager.t(
                                        "The benchmark measures the card and integrated reader; it cannot diagnose a cable.",
                                        "Il benchmark misura la scheda e il lettore integrato; non può diagnosticare un cavo."
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                } else {
                                    LabeledContent(languageManager.t("Data Type", "Tipo dati"), value: device.speedRating.connectionType)
                                    BenchmarkLinkExpectationView(linkSpeedBps: device.negotiatedSpeedBps)
                                }
                            if !device.canRunBenchmark {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(device.bsdName.isEmpty 
                                                 ? languageManager.t("Volume not mounted", "Volume non montato") 
                                                 : "\(languageManager.t("Volume not mounted", "Volume non montato")) (\(device.bsdName))")
                                                .font(.headline)
                                            Text(languageManager.t(
                                                "The volume must be mounted in the file system to run read/write benchmark tests.",
                                                "Il volume deve essere montato nel file system per poter eseguire il test di lettura e scrittura."
                                            ))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button(action: {
                                            isMounting = true
                                            mountErrorMessage = nil
                                            Task { @MainActor in
                                                defer { isMounting = false }
                                                do {
                                                    try await discovery.mountDevice(device)
                                                } catch {
                                                    mountErrorMessage = error.localizedDescription
                                                }
                                            }
                                        }) {
                                            Label(isMounting 
                                                  ? languageManager.t("Mounting...", "Montaggio...") 
                                                  : languageManager.t("Mount Volume", "Monta volume"), systemImage: "externaldrive.badge.plus")
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(isMounting)
                                    }
                                    
                                    if let err = mountErrorMessage {
                                        HStack {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.red)
                                            Text("\(languageManager.t("Mount error:", "Errore montaggio:")) \(err)")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                .padding(.vertical, 4)
                            } else {
                                Picker(languageManager.t("Test file size", "Dimensione test"), selection: $selectedTestBytes) {
                                    Text("256 MB").tag(AnalysisMetrics.compactBenchmarkBytes)
                                    Text("1 GB").tag(AnalysisMetrics.standardBenchmarkBytes)
                                    Text("4 GB").tag(AnalysisMetrics.extendedBenchmarkBytes)
                                }
                                LabeledContent(languageManager.t("Free space", "Spazio libero"), value: device.freeSpaceFormatted)
                                LabeledContent(languageManager.t("Minimum required", "Spazio minimo"), value: ByteCountFormatter.string(fromByteCount: Int64(selectedTestBytes * 2), countStyle: .file))
                                Text(languageManager.t(
                                    "The test creates an exclusive temporary file and deletes it upon completion, even if cancelled.",
                                    "Il test crea un file temporaneo esclusivo e lo rimuove al termine, anche se annullato."
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if !benchmark.isRunning {
                                    Button(languageManager.t("Start Benchmark", "Avvia benchmark")) { runTest(for: device) }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(device.freeSpace < selectedTestBytes * 2)
                                }

                                DisclosureGroup(languageManager.t("Advanced Workloads", "Carichi avanzati")) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Picker(languageManager.t("Data set", "Set di dati"), selection: $selectedAdvancedPreset) {
                                            ForEach(BenchmarkPreset.allCases) { preset in
                                                Text(advancedPresetTitle(preset)).tag(preset)
                                            }
                                        }
                                        Picker(languageManager.t("Workload", "Carico"), selection: $selectedWorkload) {
                                            ForEach(BenchmarkWorkload.allCases) { workload in
                                                Text(advancedWorkloadTitle(workload)).tag(workload)
                                            }
                                        }
                                        if selectedWorkload.usesConfigurableRandomBlockSize {
                                            Picker(languageManager.t("Random block size", "Dimensione blocco casuale"), selection: $selectedRandomBlockSize) {
                                                ForEach(RandomBenchmarkBlockSize.allCases) { blockSize in
                                                    Text(randomBlockSizeTitle(blockSize)).tag(blockSize)
                                                }
                                            }
                                        }
                                        if selectedWorkload == .stress {
                                            Picker(languageManager.t("Stress duration", "Durata stress"), selection: $stressDurationSeconds) {
                                                Text(languageManager.t("30 seconds", "30 secondi")).tag(30)
                                                Text(languageManager.t("1 minute", "1 minuto")).tag(60)
                                                Text(languageManager.t("5 minutes", "5 minuti")).tag(300)
                                                Text(languageManager.t("15 minutes", "15 minuti")).tag(900)
                                                Text(languageManager.t("30 minutes", "30 minuti")).tag(1_800)
                                                Text(languageManager.t("1 hour", "1 ora")).tag(3_600)
                                            }
                                        }

                                        LabeledContent(languageManager.t("Required free space", "Spazio libero richiesto"), value: formatBytes(advancedRequiredFreeBytes(for: device)))
                                        if selectedAdvancedPreset.requiresExplicitConfirmation {
                                            Label(languageManager.t(
                                                "This extended test requires explicit confirmation and keeps a protected free-space reserve.",
                                                "Questo test esteso richiede una conferma esplicita e mantiene una riserva di spazio libero protetta."
                                            ), systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                        }
                                        Text(languageManager.t(
                                            "Random, mixed, integrity, and stress workloads use only an exclusive temporary file. Stress writes cycle within the selected data-set quota.",
                                            "I carichi casuali, misti, di integrità e stress usano solo un file temporaneo esclusivo. Lo stress riscrive ciclicamente entro la quota del set di dati selezionato."
                                        ))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        Button(languageManager.t("Run Advanced Benchmark", "Esegui benchmark avanzato")) {
                                            requestAdvancedBenchmark(for: device)
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(benchmark.isRunning || device.freeSpace < advancedRequiredFreeBytes(for: device))
                                    }
                                    .padding(.top, 8)
                                }
                                .disabled(benchmark.isRunning)
                            }
                            }
                        } else {
                            ContentUnavailableView(
                                languageManager.t("No USB Drives", "Nessuna unità USB"),
                                systemImage: "externaldrive.badge.questionmark",
                                description: Text(languageManager.t("Connect and select a drive to start testing.", "Collega e seleziona un’unità per iniziare il test."))
                            )
                            .frame(maxWidth: .infinity, minHeight: 280)
                        }
                }

                if benchmark.isRunning {
                    GroupBox(languageManager.t("Test in Progress", "Test in corso")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                ProgressView()
                                Text(benchmark.currentPhase)
                                    .font(.headline)
                            }
                            ProgressView(value: benchmark.progress)
                            Text("\(Int((benchmark.progress * 100).rounded()))% \(languageManager.t("completed — temporary file is removed automatically upon completion.", "completato — il file temporaneo viene rimosso automaticamente al termine."))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(languageManager.t("Cancel Test", "Annulla test"), role: .cancel) { benchmark.cancel() }
                        }
                    }
                } else if let error = benchmark.errorMessage {
                    ContentUnavailableView(
                        languageManager.t("Test Incomplete", "Test non completato"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }

                if let result, let device = benchmarkDevice {
                    benchmarkResultView(result: result, device: device)
                    VideoCapabilityView(sustainedWriteMBps: result.sequentialWriteMBps, languageManager: languageManager)
                    if let score = overallScore(for: device, writeMBps: result.sequentialWriteMBps) {
                        overallScoreView(score)
                    }
                }

                if let advancedResult {
                    AdvancedBenchmarkResultView(result: advancedResult, languageManager: languageManager)
                    if let sustainedWrite = advancedResult.samples.reversed().compactMap(\.writeMBps).first {
                        VideoCapabilityView(sustainedWriteMBps: sustainedWrite, languageManager: languageManager)
                    }
                }

                if let device = benchmarkDevice {
                    recordedBenchmarkSection(for: device)
                }
            }
            .padding()
        }
        .onAppear {
            if discovery.selectedDevice == nil || discovery.selectedDevice?.isStorageDevice != true {
                if let target = benchmarkDevice ?? storageDevices.first {
                    discovery.selectedDevice = target
                }
            }
        }
        .onChange(of: discovery.devices) { _, _ in
            if discovery.selectedDevice == nil || discovery.selectedDevice?.isStorageDevice != true {
                if let target = benchmarkDevice ?? storageDevices.first {
                    discovery.selectedDevice = target
                }
            }
        }
        .confirmationDialog(
            languageManager.t("Confirm Extended Benchmark", "Conferma benchmark esteso"),
            isPresented: $showExtendedTestConfirmation,
            titleVisibility: .visible
        ) {
            Button(languageManager.t("Run Extended Test", "Esegui test esteso")) {
                confirmedExtendedPreset = selectedAdvancedPreset
                if let device = benchmarkDevice {
                    runAdvancedBenchmark(for: device)
                }
            }
            Button(languageManager.t("Cancel", "Annulla"), role: .cancel) {}
        } message: {
            Text(languageManager.t(
                "This test can create a temporary file up to the selected size. Existing files are not modified and the app preserves the required free-space reserve.",
                "Questo test può creare un file temporaneo fino alla dimensione selezionata. I file esistenti non vengono modificati e l’app conserva la riserva di spazio libero richiesta."
            ))
        }
    }

    private func runTest(for device: DriveDevice) {
        Task {
            do {
                let completed = try await benchmark.runBenchmark(mountPath: device.mountPath, config: BenchmarkConfig(testSizeBytes: selectedTestBytes))
                result = completed
                advancedResult = nil
                let fingerprint = discovery.connectionFingerprint(for: device)
                let id = historyStore.upsertAutomaticResult(for: device, fingerprint: fingerprint)
                historyStore.attachBenchmark(completed, to: id)
            } catch {
                benchmark.errorMessage = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func benchmarkResultView(result: BenchmarkResult, device: DriveDevice) -> some View {
        let expectation = BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: device.negotiatedSpeedBps)
        GroupBox(languageManager.t("Benchmark Result", "Risultato")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(languageManager.t("Measured Speeds", "Velocità misurate"))
                        .font(.headline)
                    Spacer()
                    Text(String(format: "%@: %.1f s", languageManager.t("Duration", "Durata"), result.durationSeconds))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(languageManager.t("Read", "Lettura"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f MB/s", result.sequentialReadMBps))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.blue)
                        if let exp = expectation {
                            let readPct = min(100, Int((result.sequentialReadMBps / exp.realisticMaximumMBps * 100).rounded()))
                            Text("\(readPct)% \(languageManager.t("of expected link max", "del max reale link"))")
                                .font(.caption2)
                                .foregroundStyle(readPct >= 80 ? .green : .secondary)
                        }
                    }
                    
                    Divider()
                        .frame(height: 45)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(languageManager.t("Write", "Scrittura"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f MB/s", result.sequentialWriteMBps))
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                        if let exp = expectation {
                            let writePct = min(100, Int((result.sequentialWriteMBps / exp.realisticMaximumMBps * 100).rounded()))
                            Text("\(writePct)% \(languageManager.t("of expected link max", "del max reale link"))")
                                .font(.caption2)
                                .foregroundStyle(writePct >= 80 ? .green : .secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                
                Divider()
                
                if let exp = expectation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("Expected for this Connection", "Velocità attese per questa connessione"))
                            .font(.subheadline.weight(.semibold))
                        
                        LabeledContent(
                            languageManager.t("Expected real-world range", "Velocità reale attesa del canale"),
                            value: exp.realisticRangeFormatted
                        )
                        LabeledContent(
                            languageManager.t("Theoretical link max", "Massimo teorico del link"),
                            value: "\(exp.theoreticalMaxFormatted) (\(exp.protocolName))"
                        )
                    }
                    
                    Divider()
                    
                    performanceInsightView(result: result, expectation: exp)
                    
                    Divider()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(languageManager.t("Daily Use Assessment", "Valutazione per uso quotidiano"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(usageAssessment(writeMBps: result.sequentialWriteMBps), id: \.self) { Text($0).font(.caption) }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func performanceInsightView(result: BenchmarkResult, expectation: BenchmarkLinkExpectation) -> some View {
        let isReadSaturatingLink = result.sequentialReadMBps >= expectation.minimumMBps * 0.90
        let isWriteSaturatingLink = result.sequentialWriteMBps >= expectation.minimumMBps * 0.85
        
        if isReadSaturatingLink && !isWriteSaturatingLink {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.body)
                VStack(alignment: .leading, spacing: 3) {
                    Text(languageManager.t("Cable & Port operating at maximum speed", "Cavo e porta operano alla massima velocità"))
                        .font(.caption.weight(.bold))
                    Text(languageManager.t(
                        "The read speed (\(String(format: "%.1f", result.sequentialReadMBps)) MB/s) saturates the USB link, confirming the cable and port are performing at 100%. The lower write speed (\(String(format: "%.1f", result.sequentialWriteMBps)) MB/s) is limited by the internal flash memory of the drive, not the connection.",
                        "La velocità di lettura (\(String(format: "%.1f", result.sequentialReadMBps)) MB/s) satura il link USB, confermando che il cavo e la porta funzionano al 100%. La velocità di scrittura inferiore (\(String(format: "%.1f", result.sequentialWriteMBps)) MB/s) è limitata dalla memoria flash interna dell'unità, non dalla connessione o dal cavo."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if isReadSaturatingLink && isWriteSaturatingLink {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(languageManager.t("Optimal Read & Write Performance", "Prestazioni di Lettura e Scrittura ottimali"))
                        .font(.caption.weight(.bold))
                    Text(languageManager.t(
                        "Both read and write speeds fully saturate the \(expectation.protocolName) connection.",
                        "Sia la lettura che la scrittura sfruttano appieno la larghezza di banda della connessione \(expectation.protocolName)."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(languageManager.t("Drive-limited transfer speeds", "Velocità limitate dall'unità"))
                        .font(.caption.weight(.bold))
                    Text(languageManager.t(
                        "The speeds are below the link's maximum capability (\(expectation.realisticRangeFormatted)). This is normal for USB flash drives, mechanical hard drives (HDD), or shared USB hubs.",
                        "Le velocità sono inferiori al massimo consentito dal link (\(expectation.realisticRangeFormatted)). Questo è normale per chiavette USB standard, dischi meccanici (HDD) o hub USB condivisi."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func recordedBenchmarkSection(for device: DriveDevice) -> some View {
        let stdBenchmarks = historyStore.benchmarkHistory(for: device)
        let advBenchmarks = historyStore.advancedBenchmarkHistory(for: device)
        
        if !stdBenchmarks.isEmpty || !advBenchmarks.isEmpty {
            GroupBox(languageManager.t("Recorded Benchmark History", "Storico test registrati su questa unità")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.blue)
                        Text(languageManager.t("Previous Test Results", "Risultati dei test precedenti"))
                            .font(.headline)
                        Spacer()
                        Text("\(stdBenchmarks.count + advBenchmarks.count) \(languageManager.t("tests", "test"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(stdBenchmarks) { test in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Label(
                                    languageManager.t("Standard Sequential", "Sequenziale standard"),
                                    systemImage: "speedometer"
                                )
                                .font(.subheadline.weight(.semibold))
                                
                                Spacer()
                                
                                Text(test.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack(spacing: 24) {
                                if let read = test.benchmarkReadMBps {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(languageManager.t("Read", "Lettura"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.1f MB/s", read))
                                            .font(.callout.weight(.bold))
                                            .monospacedDigit()
                                            .foregroundStyle(.blue)
                                    }
                                }
                                if let write = test.benchmarkWriteMBps {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(languageManager.t("Write", "Scrittura"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.1f MB/s", write))
                                            .font(.callout.weight(.bold))
                                            .monospacedDigit()
                                            .foregroundStyle(.orange)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(languageManager.t("Link Speed", "Velocità Link"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(test.linkSpeedFormatted)
                                        .font(.callout.weight(.medium))
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    ForEach(advBenchmarks) { rec in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Label(
                                    "\(languageManager.t("Advanced", "Avanzato")): \(advancedWorkloadTitle(rec.result.configuration.workload)) (\(advancedPresetTitle(rec.result.configuration.preset)))",
                                    systemImage: "waveform.path.ecg"
                                )
                                .font(.subheadline.weight(.semibold))
                                
                                Spacer()
                                
                                Text(rec.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            HStack(spacing: 24) {
                                if let read = rec.result.samples.reversed().compactMap(\.readMBps).first {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(languageManager.t("Read", "Lettura"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.1f MB/s", read))
                                            .font(.callout.weight(.bold))
                                            .monospacedDigit()
                                            .foregroundStyle(.blue)
                                    }
                                }
                                if let write = rec.result.samples.reversed().compactMap(\.writeMBps).first {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(languageManager.t("Write", "Scrittura"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.1f MB/s", write))
                                            .font(.callout.weight(.bold))
                                            .monospacedDigit()
                                            .foregroundStyle(.orange)
                                    }
                                }
                                if let readIOPS = rec.result.randomReadIOPS {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("IOPS")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: "%.0f", readIOPS))
                                            .font(.callout.weight(.medium))
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func driveHealthSummary(for device: DriveDevice) -> some View {
        if device.isStorageDevice {
            GroupBox(languageManager.t("Drive Health", "Salute unità")) {
                if let snapshot = driveHealth.snapshot(for: device) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            if snapshot.smartStatus == .unavailable {
                                Text(languageManager.t("Not assessable", "Non valutabile"))
                                    .font(.title3.weight(.semibold))
                                Text(languageManager.t("SMART not available", "SMART non disponibile"))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(snapshot.assessment.score)/100")
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                                Text(driveHealthLevelTitle(snapshot.assessment.level))
                                    .foregroundStyle(driveHealthColor(snapshot.assessment.level))
                            }
                            Spacer()
                            Button(languageManager.t("Refresh", "Aggiorna")) {
                                Task { await driveHealth.refresh(device) }
                            }
                            .controlSize(.small)
                        }
                        if snapshot.smartStatus != .unavailable {
                            ProgressView(value: Double(snapshot.assessment.score), total: 100)
                                .tint(driveHealthColor(snapshot.assessment.level))
                        }
                        LabeledContent(languageManager.t("SMART", "SMART"), value: snapshot.rawSMARTStatus ?? languageManager.t("Not exposed by this connection", "Non esposto da questo collegamento"))
                        if let temperature = snapshot.temperatureCelsius {
                            LabeledContent(languageManager.t("Temperature", "Temperatura"), value: String(format: "%.0f °C", temperature))
                        }
                        if let remainingLife = snapshot.remainingLifePercent {
                            LabeledContent(languageManager.t("Estimated remaining life", "Vita residua stimata"), value: "\(remainingLife)%")
                        }
                        if let powerOnHours = snapshot.powerOnHours {
                            LabeledContent(languageManager.t("Power-on hours", "Ore di accensione"), value: "\(powerOnHours)")
                        }
                        if let powerCycles = snapshot.powerCycleCount {
                            LabeledContent(languageManager.t("Power cycles", "Cicli di accensione"), value: "\(powerCycles)")
                        }
                        if let totalBytesWritten = snapshot.totalBytesWritten {
                            LabeledContent(languageManager.t("Total written", "Totale scritto"), value: formatBytes(totalBytesWritten))
                        }
                        if let mediaErrors = snapshot.mediaErrorCount, mediaErrors > 0 {
                            LabeledContent(languageManager.t("Media errors", "Errori supporto"), value: "\(mediaErrors)")
                                .foregroundStyle(.red)
                        }
                        if snapshot.smartStatus == .unavailable {
                            Text(languageManager.t(
                                "Some USB and Thunderbolt enclosures do not expose SMART, temperature, or wear data to macOS.",
                                "Alcuni enclosure USB e Thunderbolt non espongono a macOS dati SMART, temperatura o usura."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } else {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(languageManager.t("Reading the health information macOS makes available…", "Lettura delle informazioni di salute disponibili in macOS…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task(id: device.bsdName) {
                await driveHealth.refresh(device)
            }
        }
    }

    private func driveHealthLevelTitle(_ level: DriveHealthLevel) -> String {
        switch level {
        case .excellent: languageManager.t("Excellent", "Eccellente")
        case .good: languageManager.t("Good", "Buona")
        case .warning: languageManager.t("Warning", "Attenzione")
        case .critical: languageManager.t("Critical", "Critico")
        }
    }

    private func driveHealthColor(_ level: DriveHealthLevel) -> Color {
        switch level {
        case .excellent, .good: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    @ViewBuilder
    private func connectionStabilitySummary(for device: DriveDevice) -> some View {
        GroupBox(languageManager.t("Connection Stability", "Stabilità della connessione")) {
            VStack(alignment: .leading, spacing: 7) {
                if let score = hardwareEventLog.stabilityScore(for: device) {
                    let tone: SemanticStatusTone = score >= 90 ? .success : (score >= 70 ? .warning : .error)
                    let deductions = hardwareEventLog.penaltyBreakdown(for: device)

                    HStack {
                        SemanticStatus(
                            languageManager.t("Observed session stability: \(score)/100", "Stabilità osservata nella sessione: \(score)/100"),
                            systemImage: score >= 90 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                            tone: tone
                        )
                        Spacer()
                        Button(languageManager.t("Reset", "Azzera")) {
                            hardwareEventLog.clear(for: device)
                        }
                        .controlSize(.small)
                    }

                    ProgressView(value: Double(score), total: 100)
                        .tint(score >= 90 ? .green : (score >= 70 ? .orange : .red))

                    if !deductions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(deductions, id: \.kind) { item in
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle")
                                        .foregroundStyle(.orange)
                                    Text(penaltyDescription(for: item))
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    HStack {
                        SemanticStatus(
                            languageManager.t("Stability data insufficient", "Dati di stabilità insufficienti"),
                            systemImage: "clock.badge.questionmark",
                            tone: .neutral
                        )
                        Spacer()
                    }
                }
                Text(languageManager.t(
                    "Based on live link renegotiations, abrupt bus drops, and benchmark interruptions observed during this app session. Safe ejections and manual unmounts are not penalized.",
                    "Basato su rinegoziazioni del link, disconnessioni brusche e interruzioni di benchmark osservate durante la sessione dell'app. Le normali espulsioni manuali non sono penalizzate."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }

    private func penaltyDescription(for item: StabilityPenaltyItem) -> String {
        switch item.kind {
        case .disconnected:
            return languageManager.t(
                "\(item.count) unexpected disconnection(s) (-\(item.totalDeduction) pts)",
                "\(item.count) disconnessione/i brusca/e (-\(item.totalDeduction) pt)"
            )
        case .linkRenegotiated:
            return languageManager.t(
                "\(item.count) link speed drop/renegotiation(s) (-\(item.totalDeduction) pts)",
                "\(item.count) rinegoziazione/i velocità link (-\(item.totalDeduction) pt)"
            )
        case .protocolChanged:
            return languageManager.t(
                "\(item.count) unexpected protocol change(s) (-\(item.totalDeduction) pts)",
                "\(item.count) cambio/i protocollo inatteso (-\(item.totalDeduction) pt)"
            )
        case .benchmarkFailed:
            return languageManager.t(
                "\(item.count) failed/interrupted benchmark(s) (-\(item.totalDeduction) pts)",
                "\(item.count) benchmark interrotto/i (-\(item.totalDeduction) pt)"
            )
        default:
            return languageManager.t("Anomaly detected (-\(item.totalDeduction) pts)", "Anomalia rilevata (-\(item.totalDeduction) pt)")
        }
    }

    private func overallScore(for device: DriveDevice, writeMBps: Double) -> OverallHardwareScoreResult? {
        let performance = AnalysisMetrics.linkUtilizationPercent(
            measuredMBps: writeMBps,
            linkSpeedBps: device.negotiatedSpeedBps
        ).map { min(100, $0) }
        let health = driveHealth.snapshot(for: device).flatMap { snapshot in
            snapshot.smartStatus == .unavailable ? nil : snapshot.assessment.score
        }
        return OverallHardwareScore.calculate(.init(
            connection: device.negotiatedSpeedBps == nil ? nil : 100,
            performance: performance,
            health: health,
            power: nil,
            stability: hardwareEventLog.stabilityScore(for: device)
        ))
    }

    private func overallScoreView(_ score: OverallHardwareScoreResult) -> some View {
        GroupBox(languageManager.t("Overall Hardware Score", "Punteggio hardware complessivo")) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(score.value)/100")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text(overallScoreTitle(score.level))
                        .foregroundStyle(overallScoreColor(score.level))
                    Spacer()
                }
                ProgressView(value: Double(score.value), total: 100)
                    .tint(overallScoreColor(score.level))
                Text(languageManager.t(
                    "Uses \(score.includedComponentCount) observed components: link, measured performance, available drive health, and events observed while the app is running.",
                    "Usa \(score.includedComponentCount) componenti osservati: link, prestazioni misurate, salute dell’unità disponibile ed eventi osservati mentre l’app è in esecuzione."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func overallScoreTitle(_ level: OverallHardwareScoreLevel) -> String {
        switch level {
        case .excellent: languageManager.t("Excellent", "Eccellente")
        case .good: languageManager.t("Good", "Buono")
        case .attention: languageManager.t("Attention needed", "Richiede attenzione")
        case .critical: languageManager.t("Critical", "Critico")
        }
    }

    private func overallScoreColor(_ level: OverallHardwareScoreLevel) -> Color {
        switch level {
        case .excellent, .good: .green
        case .attention: .orange
        case .critical: .red
        }
    }

    private func requestAdvancedBenchmark(for device: DriveDevice) {
        guard device.freeSpace >= advancedRequiredFreeBytes(for: device) else { return }
        if selectedAdvancedPreset.requiresExplicitConfirmation,
           confirmedExtendedPreset != selectedAdvancedPreset {
            showExtendedTestConfirmation = true
            return
        }
        runAdvancedBenchmark(for: device)
    }

    private func runAdvancedBenchmark(for device: DriveDevice) {
        let configuration = AdvancedBenchmarkConfiguration(
            preset: selectedAdvancedPreset,
            workload: selectedWorkload,
            randomBlockSize: selectedRandomBlockSize,
            stressDurationSeconds: selectedWorkload == .stress ? TimeInterval(stressDurationSeconds) : nil
        )
        Task {
            let sessionStarted = Date()
            let temperaturePollingTask = Task { @MainActor in
                while !Task.isCancelled {
                    await driveHealth.refresh(device)
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        break
                    }
                }
            }
            defer { temperaturePollingTask.cancel() }
            do {
                let completed = try await benchmark.runAdvancedBenchmark(
                    mountPath: device.mountPath,
                    configuration: configuration,
                    freeBytes: device.freeSpace,
                    volumeCapacityBytes: device.capacity,
                    userConfirmedExtendedTest: confirmedExtendedPreset == selectedAdvancedPreset
                )
                await driveHealth.refresh(device)
                let enrichedResult = completed.applyingTemperatureObservations(
                    driveHealth.temperatureHistory(for: device, since: sessionStarted)
                )
                advancedResult = enrichedResult
                result = nil
                historyStore.saveAdvancedBenchmark(enrichedResult, for: device, fingerprint: discovery.connectionFingerprint(for: device))
            } catch {
                benchmark.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func advancedRequiredFreeBytes(for device: DriveDevice) -> UInt64 {
        BenchmarkSafetyPolicy.requiredFreeBytes(
            for: selectedAdvancedPreset,
            volumeCapacityBytes: device.capacity
        )
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func advancedPresetTitle(_ preset: BenchmarkPreset) -> String {
        switch preset {
        case .quick256MiB: "256 MB"
        case .standard1GiB: "1 GB"
        case .extended5GiB: "5 GB"
        case .extended10GiB: "10 GB"
        case .fiftyGiB: "50 GB"
        case .hundredGiB: "100 GB"
        }
    }

    private func advancedWorkloadTitle(_ workload: BenchmarkWorkload) -> String {
        switch workload {
        case .sequential: languageManager.t("Sequential read and write", "Lettura e scrittura sequenziale")
        case .sustainedWrite: languageManager.t("Sustained write", "Scrittura sostenuta")
        case .random4KRead: languageManager.t("Random 4K read", "Lettura casuale 4K")
        case .random4KWrite: languageManager.t("Random 4K write", "Scrittura casuale 4K")
        case .mixedReadWrite: languageManager.t("Mixed read and write", "Lettura e scrittura mista")
        case .latency: languageManager.t("Latency", "Latenza")
        case .integrity: languageManager.t("Data integrity", "Integrità dati")
        case .stress: languageManager.t("Stress test", "Stress test")
        }
    }

    private func randomBlockSizeTitle(_ blockSize: RandomBenchmarkBlockSize) -> String {
        switch blockSize {
        case .fourKiB: "4 KiB"
        case .sixteenKiB: "16 KiB"
        case .sixtyFourKiB: "64 KiB"
        }
    }

    private func usageAssessment(writeMBps: Double) -> [String] {
        let suitable = languageManager.t("suitable", "adatta")
        let notRecommended = languageManager.t("not recommended", "non consigliata")
        let slow = languageManager.t("slow", "lenta")
        
        return [
            "\(languageManager.t("Documents", "Documenti")): \(writeMBps >= 5 ? suitable : notRecommended)",
            "\(languageManager.t("Photos", "Foto")): \(writeMBps >= 15 ? suitable : slow)",
            "\(languageManager.t("Full HD Video", "Video Full HD")): \(writeMBps >= 30 ? suitable : notRecommended)",
            "\(languageManager.t("4K Video", "Video 4K")): \(writeMBps >= 100 ? suitable : notRecommended)"
        ]
    }
}
