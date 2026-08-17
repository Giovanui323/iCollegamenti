import SwiftUI
import CAVICore

struct EDIDInspectorView: View {
    @Environment(EDIDReaderService.self) private var edidReader
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(LanguageManager.self) private var lm
    
    @State var viewMode: Mode = .interpreted
    
    enum Mode {
        case interpreted, raw
    }
    
    init(initialMode: Mode = .interpreted) {
        _viewMode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $viewMode) {
                Text(lm.t("Interpreted", "Interpretato")).tag(Mode.interpreted)
                Text(lm.t("Raw Hex", "Hex Grezzo")).tag(Mode.raw)
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)
            
            if let display = hdmiService.selectedDisplay,
               let edid = edidReader.parsedEDID(for: display.displayID) {
                if viewMode == .interpreted {
                    interpretedView(edid: edid)
                } else {
                    rawView(edid: edid)
                }
            } else {
                Text(lm.t("Reading EDID...", "Lettura EDID..."))
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
    
    @ViewBuilder
    private func interpretedView(edid: CAVICore.ParsedEDID) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(lm.t("Manufacturer Info", "Info Produttore")) {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(lm.t("Manufacturer", "Produttore"), value: edid.manufacturerName ?? edid.manufacturerCode)
                    LabeledContent(lm.t("Product Code", "Codice Prodotto"), value: "\(edid.productCode)")
                    LabeledContent(lm.t("Year", "Anno"), value: "\(edid.manufactureYear)")
                }
            }
            
            GroupBox(lm.t("Display Info", "Info Display")) {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(lm.t("Physical Size", "Dimensioni Fisiche"), value: "\(String(format: "%.1f", edid.screenWidthCm)) cm × \(String(format: "%.1f", edid.screenHeightCm)) cm")
                    LabeledContent(lm.t("Gamma", "Gamma"), value: edid.gamma != nil ? String(format: "%.2f", edid.gamma!) : "-")
                }
            }
        }
    }
    
    @ViewBuilder
    private func rawView(edid: CAVICore.ParsedEDID) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button(lm.t("Copy Hex", "Copia Hex"), systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(edid.rawHexDump, forType: .string)
                }
            }
            
            ScrollView {
                Text(edid.rawHexDump)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 500)
            .padding()
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            
            if let cta = edid.ctaExtension {
                NativeSectionHeader(lm.t("CTA-861 Extension", "Estensione CTA-861"))
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Revision \(cta.revision)")
                        Text("\(cta.rawDataBlocks.count) Data Blocks")
                    }
                }
            }
        }
    }
}
