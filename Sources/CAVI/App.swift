import SwiftUI
import AppKit

@main
struct CAVIApp: App {
    @State private var discoveryService = DeviceDiscoveryService()
    @State private var historyStore = TestHistoryStore()
    @State private var bottleneckAnalyzer = BottleneckAnalyzerService()
    @State private var benchmarkService = BenchmarkService()
    @State private var ioMonitor = DiskIOMonitorService()
    @State private var hdmiService = HDMIDisplayDiscoveryService()
    @State private var macChargingService = MacChargingService()
    @State private var chargerProfileStore = ChargerProfileStore()
    @State private var languageManager = LanguageManager()
    @State private var usbVendorCatalog = USBVendorCatalog()
    @State private var usbCableEvidence = USBCableEvidenceDiscoveryService()
    @State private var hardwareEventLog = HardwareEventLog()
    @State private var driveHealthService = DriveHealthService()
    
    // HDMI Services
    @State private var edidReaderService = EDIDReaderService()
    @State private var hdmiAnalysisService = HDMIDisplayAnalysisService()
    @State private var hdmiCapabilityTestService = HDMICapabilityTestService()
    @State private var hdmiStressTestService = HDMIStressTestService()
    @State private var hdmiCableHistoryStore = HDMICableHistoryStore()
    
    var body: some Scene {
        WindowGroup("iCollegamenti") {
            ContentView()
                .environment(languageManager)
                .environment(discoveryService)
                .environment(historyStore)
                .environment(bottleneckAnalyzer)
                .environment(benchmarkService)
                .environment(ioMonitor)
                .environment(hdmiService)
                .environment(macChargingService)
                .environment(chargerProfileStore)
                .environment(usbVendorCatalog)
                .environment(usbCableEvidence)
                .environment(hardwareEventLog)
                .environment(driveHealthService)
                .environment(edidReaderService)
                .environment(hdmiAnalysisService)
                .environment(hdmiCapabilityTestService)
                .environment(hdmiStressTestService)
                .environment(hdmiCableHistoryStore)
                .environment(\.locale, languageManager.currentLanguage.locale)
                .onAppear {
                    discoveryService.attachVendorCatalog(usbVendorCatalog)
                    discoveryService.attachEventLog(hardwareEventLog)
                    benchmarkService.attachEventLog(hardwareEventLog)
                    discoveryService.startMonitoring()
                    usbCableEvidence.refresh()
                    Task {
                        await usbVendorCatalog.update()
                        discoveryService.refreshDevices()
                    }
                    hdmiService.startMonitoring()
                    macChargingService.startMonitoring()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    
                    // Trigger EDID read
                    let displayIDs = hdmiService.externalDisplays.map { $0.displayID }
                    edidReaderService.readAllEDIDs(displayIDs: displayIDs)
                }
                .onChange(of: discoveryService.devices) { _, _ in
                    usbCableEvidence.refresh()
                }
                .onChange(of: hdmiService.externalDisplays) { _, displays in
                    edidReaderService.readAllEDIDs(displayIDs: displays.map { $0.displayID })
                }
                .onDisappear {
                    discoveryService.stopMonitoring()
                    ioMonitor.stopMonitoring()
                    hdmiService.stopMonitoring()
                    macChargingService.stopMonitoring()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_000, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(languageManager.t("About iCollegamenti", "Informazioni su iCollegamenti")) {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "iCollegamenti",
                            .version: "1.0"
                        ]
                    )
                }
            }
            CommandMenu(languageManager.t("Language", "Lingua")) {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        languageManager.selectLanguage(lang)
                    } label: {
                        HStack {
                            Text("\(lang.flag) \(lang.displayName)")
                            if languageManager.currentLanguage == lang {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button(languageManager.t("Choose Language...", "Scegli lingua...")) {
                    languageManager.promptLanguageSelection()
                }
            }
            InspectorCommands()
            CommandGroup(after: .toolbar) {
                Button(languageManager.t("Refresh", "Aggiorna")) {
                    NotificationCenter.default.post(name: .refreshCAVIData, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
