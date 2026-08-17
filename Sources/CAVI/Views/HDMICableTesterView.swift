import SwiftUI
import CAVICore

struct HDMICableTesterView: View {
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(EDIDReaderService.self) private var edidReader
    @Environment(LanguageManager.self) private var lm
    
    @State private var selectedTab: HDMITab = .signal
    
    enum HDMITab: String, CaseIterable, Identifiable {
        case signal, display, edidRaw, audio, test, patterns, cable, chain, diagnosis
        var id: Self { self }
        
        func title(lm: LanguageManager) -> String {
            switch self {
            case .signal: return lm.t("Signal", "Segnale")
            case .display: return lm.t("Display", "Monitor")
            case .edidRaw: return lm.t("EDID", "EDID")
            case .audio: return lm.t("Audio", "Audio")
            case .test: return lm.t("Test", "Test")
            case .patterns: return lm.t("Patterns", "Motivi")
            case .cable: return lm.t("Cable", "Cavo")
            case .chain: return lm.t("Chain", "Catena")
            case .diagnosis: return lm.t("Diagnosis", "Diagnosi")
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            displayPicker
                .padding()
            
            if hdmiService.selectedDisplay != nil {
                tabBar
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                
                Divider()
                
                ScrollView {
                    tabContent
                        .padding()
                }
            } else {
                ContentUnavailableView(
                    lm.t("No External Display", "Nessun monitor esterno"),
                    systemImage: "display",
                    description: Text(lm.t("Connect a monitor or TV and refresh the list.", "Collega un monitor o una TV e aggiorna l’elenco."))
                )
            }
        }
        .task { 
            let ids = hdmiService.externalDisplays.map(\.displayID)
            edidReader.readAllEDIDs(displayIDs: ids)
        }
        .onChange(of: hdmiService.externalDisplays) { _, newDisplays in
            let ids = newDisplays.map(\.displayID)
            edidReader.readAllEDIDs(displayIDs: ids)
        }
    }
    
    @MainActor
    private var displayPicker: some View {
        HStack {
            Text(lm.t("Display:", "Monitor:"))
                .font(.headline)
            
            if hdmiService.externalDisplays.isEmpty {
                Text(lm.t("No external display", "Nessun monitor esterno"))
                    .foregroundStyle(.secondary)
            } else {
                @Bindable var service = hdmiService
                Picker(lm.t("Display", "Monitor"), selection: $service.selectedDisplay) {
                    ForEach(hdmiService.externalDisplays) { display in
                        Text(display.displayName).tag(Optional(display))
                    }
                }
                .labelsHidden()
            }
            
            Spacer()
            
            Button(action: { hdmiService.refreshDisplays() }) {
                Image(systemName: "arrow.clockwise")
            }
            .help(lm.t("Refresh Displays", "Aggiorna display"))
        }
    }
    
    private var tabBar: some View {
        Picker("Tabs", selection: $selectedTab) {
            ForEach(HDMITab.allCases) { tab in
                Text(tab.title(lm: lm)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .signal:
            HDMISignalView()
        case .display, .edidRaw:
            EDIDInspectorView(initialMode: selectedTab == .display ? .interpreted : .raw)
        case .audio:
            HDMIAudioInspectorView()
        case .test:
            HDMICapabilityTestView()
        case .patterns:
            HDMIPatternView()
        case .cable:
            HDMICableComparisonView()
        case .chain:
            HDMIChainVisualizerView()
        case .diagnosis:
            HDMIDiagnosisView()
        }
    }
}
