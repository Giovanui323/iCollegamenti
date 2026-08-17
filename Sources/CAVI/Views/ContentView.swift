import SwiftUI
import AppKit

private enum Destination: String, CaseIterable, Identifiable {
    case usb, video, charging, peripherals, flashDrive, history, wizard
    
    var id: Self { self }
    
    func title(using lm: LanguageManager) -> String {
        switch self {
        case .usb: return lm.t("Connections", "Collegamenti")
        case .video: return lm.t("Video", "Video")
        case .charging: return lm.t("Charging", "Ricarica")
        case .peripherals: return lm.t("Peripherals", "Periferiche")
        case .flashDrive: return lm.t("Drives & Benchmark", "Unità e benchmark")
        case .history: return lm.t("History", "Cronologia")
        case .wizard: return lm.t("Guided Wizard", "Diagnosi guidata")
        }
    }
    
    var symbol: String {
        switch self {
        case .usb: return "cable.connector"
        case .video: return "display"
        case .charging: return "bolt.batteryblock.fill"
        case .peripherals: return "point.3.connected.trianglepath.dotted"
        case .flashDrive: return "externaldrive.fill"
        case .history: return "clock.arrow.circlepath"
        case .wizard: return "checkmark.seal.fill"
        }
    }
}

extension Notification.Name {
    static let refreshCAVIData = Notification.Name("refreshCAVIData")
}

struct ContentView: View {
    @State private var selection: Destination? = .usb
    @State private var isInspectorPresented = false
    @Environment(LanguageManager.self) private var languageManager
    @Environment(DeviceDiscoveryService.self) private var discoveryService
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(USBCableEvidenceDiscoveryService.self) private var usbCableEvidence
    @Environment(TestHistoryStore.self) private var historyStore
    @Environment(HardwareEventLog.self) private var hardwareEventLog

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $selection) { destination in
                Label(destination.title(using: languageManager), systemImage: destination.symbol)
                    .tag(destination)
            }
            .navigationTitle("iCollegamenti")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
        } detail: {
            destinationView
            .navigationTitle(selection?.title(using: languageManager) ?? languageManager.t("Connections", "Collegamenti"))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(languageManager.t("Refresh", "Aggiorna"), systemImage: "arrow.clockwise", action: refreshAll)
                    .help(languageManager.t("Refresh connected devices and displays", "Aggiorna i dispositivi e i display collegati"))

                    Menu {
                        Button(languageManager.t("Export Markdown Report", "Esporta Report Markdown"), systemImage: "doc.text") {
                            saveReport(historyStore.exportMarkdown(language: languageManager.currentLanguage, events: hardwareEventLog.events), filename: "Report_iCollegamenti.md")
                        }
                        Button(languageManager.t("Export CSV Data", "Esporta Dati CSV"), systemImage: "tablecells") {
                            saveReport(historyStore.exportCSV(), filename: "Cavi_iCollegamenti.csv")
                        }
                        Button(languageManager.t("Export JSON Data", "Esporta Dati JSON"), systemImage: "curlybraces") {
                            saveReport(historyStore.exportJSON(), filename: "Cavi_iCollegamenti.json")
                        }
                        Button(languageManager.t("Export Diagnostic JSON", "Esporta JSON diagnostico"), systemImage: "curlybraces.square") {
                            saveReport(historyStore.exportDiagnosticJSON(events: hardwareEventLog.events), filename: "Diagnostica_iCollegamenti.json")
                        }
                        Button(languageManager.t("Export Event Log", "Esporta Log Eventi"), systemImage: "list.bullet.rectangle") {
                            saveReport(hardwareEventLog.exportPlainText(), filename: "Eventi_iCollegamenti.txt")
                        }
                        Button(languageManager.t("Export Plain Text Report", "Esporta report testo"), systemImage: "doc.plaintext") {
                            saveReport(historyStore.exportPlainText(language: languageManager.currentLanguage, events: hardwareEventLog.events), filename: "Report_iCollegamenti.txt")
                        }
                        Button(languageManager.t("Export PDF Report", "Esporta Report PDF"), systemImage: "doc.richtext") {
                            savePDFReport(historyStore.exportMarkdown(language: languageManager.currentLanguage, events: hardwareEventLog.events), filename: "Report_iCollegamenti.pdf")
                        }
                    } label: {
                        Label(languageManager.t("Export Report", "Esporta Report"), systemImage: "square.and.arrow.up")
                    }
                    .help(languageManager.t("Export saved test results", "Esporta i risultati salvati"))

                    Button {
                        isInspectorPresented.toggle()
                    } label: {
                        Label(languageManager.t("Toggle Inspector", "Mostra Inspector"), systemImage: "sidebar.right")
                    }
                    .help(languageManager.t("Show or hide technical details", "Mostra o nasconde i dettagli tecnici"))
                    .accessibilityLabel(languageManager.t("Toggle Inspector", "Mostra o nasconde Inspector"))
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, minHeight: 520)
        .inspector(isPresented: $isInspectorPresented) {
            InspectorDetailsView(
                device: inspectorDevice,
                display: selection == .video ? hdmiService.selectedDisplay : nil
            )
        }
        .sheet(isPresented: Bindable(languageManager).showLanguagePrompt) {
            LanguageSelectionSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshCAVIData)) { _ in
            refreshAll()
        }
    }

    @ViewBuilder private var destinationView: some View {
        switch selection ?? .usb {
        case .usb: CableTesterMainView()
        case .video: HDMICableTesterView()
        case .charging: ChargingSpeedView()
        case .peripherals: USBConnectionsView()
        case .flashDrive: USBFlashDriveTesterView()
        case .history: CableLeaderboardView()
        case .wizard: GuidedCableWizardView()
        }
    }

    private var inspectorDevice: DriveDevice? {
        switch selection {
        case .usb, .peripherals, .flashDrive, .wizard:
            discoveryService.selectedDevice
        case .charging, .video, .history, .none:
            nil
        }
    }
    
    private func saveReport(_ text: String, filename: String) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func savePDFReport(_ text: String, filename: String) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = filename
        savePanel.allowedContentTypes = [.pdf]
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? PDFReportRenderer.write(report: text, to: url)
        }
    }

    private func refreshAll() {
        discoveryService.refreshDevices()
        hdmiService.refreshDisplays()
        usbCableEvidence.refresh()
    }
}
