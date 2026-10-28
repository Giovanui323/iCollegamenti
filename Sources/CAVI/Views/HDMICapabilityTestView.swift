import SwiftUI
import CAVICore

struct HDMICapabilityTestView: View {
    @Environment(HDMICapabilityTestService.self) private var capabilityTest
    @Environment(HDMIStressTestService.self) private var stressTest
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(EDIDReaderService.self) private var edidReader
    @Environment(LanguageManager.self) private var lm
    
    @State private var stressDurationMins: Int = 5
    
    var body: some View {
        VStack(spacing: 24) {
            if let display = hdmiService.selectedDisplay {
                HStack(alignment: .top, spacing: 24) {
                    VStack(spacing: 24) {
                        capabilitySection(display: display)
                        stressTestSection(display: display)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(spacing: 24) {
                        scoreSection
                        compatibilityMatrixSection(display: display)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Text(lm.t("No display selected", "Nessun display selezionato"))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func capabilitySection(display: HDMIDisplayDevice) -> some View {
        GroupBox(lm.t("Progressive Capability Test", "Test di Capacità Progressivo")) {
            VStack(alignment: .leading, spacing: 16) {
                let isRunning = capabilityTest.isRunning
                
                HStack {
                    Button(isRunning ? lm.t("Stop Test", "Ferma Test") : lm.t("Start Test", "Avvia Test")) {
                        if isRunning {
                            capabilityTest.stopTest(for: display.displayID)
                        } else {
                            capabilityTest.startTest(for: display.displayID)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRunning ? .red : .blue)
                    
                    if isRunning {
                        ProgressView()
                            .padding(.leading, 8)
                    }
                }
                
                let results = capabilityTest.results(for: display.displayID)
                if !results.isEmpty {
                    List(results) { entry in
                        HStack {
                            Text(entry.modeDescription)
                            Spacer()
                            statusIcon(for: entry.status)
                        }
                    }
                    .frame(height: 200)
                    .listStyle(.plain)
                    .border(Color.secondary.opacity(0.2))
                }
                
                if let maxMode = capabilityTest.highestVerifiedMode(for: display.displayID) {
                    VStack(alignment: .leading) {
                        Text(lm.t("Maximum Stable Mode", "Modalità Stabile Massima"))
                            .font(.headline)
                        Text(maxMode.modeDescription)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.green)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private func compatibilityMatrixSection(display: HDMIDisplayDevice) -> some View {
        GroupBox(lm.t("Compatibility Matrix", "Matrice di Compatibilità")) {
            let matrix = capabilityTest.compatibilityMatrix(for: display.displayID, edid: edidReader.parsedEDID(for: display.displayID))
            
            if matrix.isEmpty {
                Text(lm.t("No EDID modes available. Run the test to populate the matrix.", "Nessuna modalità EDID disponibile. Esegui il test per popolare la matrice."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List(matrix) { row in
                    HStack {
                        Text("\(row.mode.width)×\(row.mode.height)")
                            .fontWeight(row.mode.isNative ? .semibold : .regular)
                            .frame(width: 110, alignment: .leading)
                        Text("\(Int(row.mode.refreshRate.rounded())) Hz").frame(width: 60, alignment: .leading)
                        Text(String(format: "%.1f Gb/s", row.requiredBandwidthGbps))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(row.fitsAdvertisedLink == false ? .orange : .secondary)
                            .frame(width: 80, alignment: .leading)
                            .help(linkHelp(row.fitsAdvertisedLink))
                        if row.mode.source == .testedByMac {
                            Text(lm.t("not in EDID", "non nell'EDID"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusIcon(for: row.testStatus)
                    }
                }
                .frame(minHeight: 300)
            }
        }
    }
    
    @ViewBuilder
    private func stressTestSection(display: HDMIDisplayDevice) -> some View {
        GroupBox(lm.t("Stress Test", "Stress Test")) {
            VStack(alignment: .leading, spacing: 16) {
                let isRunning = stressTest.isRunning
                
                HStack {
                    Picker(lm.t("Duration", "Durata"), selection: $stressDurationMins) {
                        Text("1 min").tag(1)
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("60 min").tag(60)
                    }
                    .disabled(isRunning)
                    .frame(width: 150)
                    
                    Spacer()
                    
                    Button(isRunning ? lm.t("Stop", "Ferma") : lm.t("Start", "Avvia")) {
                        if isRunning {
                            stressTest.stop(for: display.displayID)
                        } else {
                            stressTest.start(for: display.displayID, durationMinutes: stressDurationMins)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRunning ? .red : .orange)
                }
                
                let events = stressTest.events(for: display.displayID)
                if !events.isEmpty {
                    List(events) { event in
                        HStack {
                            Text(event.timestamp, style: .time)
                                .font(.caption.monospacedDigit())
                            Text(event.description)
                            Spacer()
                            eventIcon(for: event.eventType)
                        }
                    }
                    .frame(height: 150)
                    .listStyle(.plain)
                    .border(Color.secondary.opacity(0.2))
                }
            }
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private var scoreSection: some View {
        if let display = hdmiService.selectedDisplay {
            let score = capabilityTest.stabilityScore(for: display.displayID)
            
            GroupBox(lm.t("HDMI Stability Score", "Punteggio Stabilità HDMI")) {
                VStack {
                    Gauge(value: score, in: 0...100) {
                        Text(lm.t("Score", "Punteggio"))
                    } currentValueLabel: {
                        Text("\(Int(score))")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(score > 80 ? .green : (score > 50 ? .orange : .red))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .scaleEffect(1.5)
                    .padding(32)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    private func linkHelp(_ fits: Bool?) -> String {
        switch fits {
        case true?: lm.t("Fits the link capacity the display states (8-bit RGB).", "Rientra nella capacità del link dichiarata dal monitor (RGB 8 bit).")
        case false?: lm.t("Exceeds the link capacity the display states: needs subsampling or compression.", "Supera la capacità del link dichiarata dal monitor: serve sottocampionamento o compressione.")
        case nil: lm.t("The display does not state a link capacity.", "Il monitor non dichiara la capacità del link.")
        }
    }

    private func statusIcon(for status: HDMICapabilityTestStatus) -> some View {
        Group {
            switch status {
            case .pass:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .fail:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .skipped:
                Image(systemName: "slash.circle.fill").foregroundStyle(.gray)
            case .untested:
                Image(systemName: "hourglass").foregroundStyle(.secondary)
            }
        }
    }
    
    private func eventIcon(for type: HDMIStressEventType) -> some View {
        Group {
            switch type {
            case .disconnect, .signalLoss:
                Image(systemName: "bolt.horizontal.fill").foregroundStyle(.red)
            case .reconnect, .signalRestore:
                Image(systemName: "bolt.horizontal.fill").foregroundStyle(.green)
            case .modeChange, .renegotiation:
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.blue)
            case .hdcpFailure:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}
