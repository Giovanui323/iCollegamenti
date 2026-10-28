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
            } else if hdmiService.selectedDisplay != nil {
                Text(lm.t("EDID not available for this display.", "EDID non disponibile per questo display."))
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                Text(lm.t("No display selected.", "Nessun display selezionato."))
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
    
    @ViewBuilder
    private func interpretedView(edid: CAVICore.ParsedEDID) -> some View {
        let yes = lm.t("Yes", "Sì")
        let no = lm.t("No", "No")
        VStack(alignment: .leading, spacing: 16) {
            if !edid.isChecksumValid {
                Label(
                    lm.t("The EDID checksum is wrong. The data below may be corrupted by the cable, adapter or display.",
                         "Il checksum dell'EDID è errato. I dati qui sotto potrebbero essere corrotti da cavo, adattatore o monitor."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }

            GroupBox(lm.t("Manufacturer Info", "Info Produttore")) {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(lm.t("Manufacturer", "Produttore"), value: edid.manufacturerName ?? edid.manufacturerCode)
                    if let model = edid.manufactureName {
                        LabeledContent(lm.t("Model", "Modello"), value: model)
                    }
                    LabeledContent(lm.t("Product Code", "Codice Prodotto"), value: String(format: "0x%04X", edid.productCode))
                    if let serial = edid.serialString {
                        LabeledContent(lm.t("Serial", "Seriale"), value: serial)
                    }
                    LabeledContent(lm.t("Manufactured", "Fabbricazione"), value: edid.manufactureWeek > 0 && edid.manufactureWeek <= 53
                        ? lm.t("Week \(edid.manufactureWeek), \(edid.manufactureYear)", "Settimana \(edid.manufactureWeek), \(edid.manufactureYear)")
                        : "\(edid.manufactureYear)")
                    LabeledContent(lm.t("EDID Version", "Versione EDID"), value: edid.edidVersion)
                    LabeledContent("Checksum", value: edid.isChecksumValid ? lm.t("Valid", "Valido") : lm.t("Invalid", "Non valido"))
                }
            }

            GroupBox(lm.t("Display Info", "Info Display")) {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(lm.t("Physical Size", "Dimensioni Fisiche"), value: "\(edid.screenWidthCm) cm × \(edid.screenHeightCm) cm")
                    LabeledContent(lm.t("Gamma", "Gamma"), value: edid.gamma.map { String(format: "%.2f", $0) } ?? "-")
                    if let timing = edid.detailedTimings.first {
                        LabeledContent(lm.t("Native Mode", "Modalità Nativa"), value: String(format: "%d × %d @ %.2f Hz", timing.hActive, timing.vActive, timing.refreshRate))
                        LabeledContent(lm.t("Pixel Clock", "Pixel Clock"), value: String(format: "%.2f MHz", Double(timing.pixelClockKHz) / 1_000))
                    }
                    LabeledContent(lm.t("Colour Formats", "Formati Colore"), value: colourFormats(edid))
                    if let colorimetry = edid.ctaExtension?.colorimetry, !colorimetry.isEmpty {
                        LabeledContent(lm.t("Colorimetry", "Colorimetria"), value: colorimetry.joined(separator: ", "))
                    }
                }
            }

            if let cta = edid.ctaExtension {
                GroupBox(lm.t("HDMI Interface", "Interfaccia HDMI")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let hdmi = cta.hdmiVendorBlock {
                            LabeledContent(lm.t("Max TMDS Clock", "Clock TMDS Max"), value: hdmi.maxTMDSClockMHz.map { "\($0) MHz" } ?? "-")
                            if let frl = hdmi.maxFRLRateGbps {
                                LabeledContent(lm.t("Max FRL Rate (HDMI 2.1)", "Velocità FRL Max (HDMI 2.1)"), value: "\(frl) Gb/s")
                            }
                            LabeledContent(lm.t("Deep Colour", "Deep Color"), value: deepColour(hdmi))
                            LabeledContent("3D", value: hdmi.supports3D ? yes : no)
                        } else {
                            Text(lm.t("No HDMI vendor block: the display may be DisplayPort-only or limited to HDMI 1.x basics.",
                                      "Nessun blocco HDMI: il monitor potrebbe essere solo DisplayPort o limitato alle funzioni base HDMI 1.x."))
                                .foregroundStyle(.secondary)
                        }
                        if let capacity = edid.advertisedLinkCapacityGbps {
                            LabeledContent(lm.t("Stated Link Capacity", "Capacità Link Dichiarata"), value: String(format: "%.1f Gb/s", capacity))
                        }
                    }
                }

                GroupBox(lm.t("HDR & Variable Refresh", "HDR e Refresh Variabile")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let hdr = cta.hdrCapabilities {
                            LabeledContent("HDR10 (PQ)", value: hdr.supportsSMPTE_ST_2084 ? yes : no)
                            LabeledContent("HLG", value: hdr.supportsHLG ? yes : no)
                            if let maxLuminance = hdr.maxLuminanceCdm2 {
                                LabeledContent(lm.t("Peak Luminance", "Luminanza di Picco"), value: String(format: "%.0f cd/m²", maxLuminance))
                            }
                            if let average = hdr.maxFrameAverageLuminance {
                                LabeledContent(lm.t("Max Frame-Average", "Media Max Fotogramma"), value: String(format: "%.0f cd/m²", average))
                            }
                            if let minimum = hdr.minLuminanceCdm2 {
                                LabeledContent(lm.t("Minimum Luminance", "Luminanza Minima"), value: String(format: "%.4f cd/m²", minimum))
                            }
                        } else {
                            LabeledContent("HDR", value: lm.t("Not advertised", "Non dichiarato"))
                        }
                        LabeledContent("VRR", value: cta.vrrRange.map { "\($0.minRefreshHz)–\($0.maxRefreshHz) Hz" } ?? lm.t("Not advertised", "Non dichiarato"))
                    }
                }
            }

            let modes = edid.advertisedModes
            if !modes.isEmpty {
                GroupBox(lm.t("Advertised Video Modes (\(modes.count))", "Modalità Video Dichiarate (\(modes.count))")) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(modes) { mode in
                            HStack {
                                Text("\(mode.width) × \(mode.height)")
                                    .fontWeight(mode.isNative ? .semibold : .regular)
                                    .frame(width: 120, alignment: .leading)
                                Text(String(format: "%.0f Hz", mode.refreshRate))
                                    .frame(width: 60, alignment: .leading)
                                if mode.isNative {
                                    Text(lm.t("native", "nativa"))
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                                Spacer()
                            }
                            .font(.callout.monospacedDigit())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func colourFormats(_ edid: CAVICore.ParsedEDID) -> String {
        var formats = ["RGB 4:4:4"]
        if edid.supportsYCbCr444 || edid.ctaExtension?.supportsYCbCr444 == true { formats.append("YCbCr 4:4:4") }
        if edid.supportsYCbCr422 || edid.ctaExtension?.supportsYCbCr422 == true { formats.append("YCbCr 4:2:2") }
        if edid.ctaExtension?.supportsYCbCr420 == true { formats.append("YCbCr 4:2:0") }
        return formats.joined(separator: ", ")
    }

    private func deepColour(_ hdmi: CAVICore.HDMIVendorBlock) -> String {
        let depths = [(hdmi.supportsDeepColor30bit, "30-bit"), (hdmi.supportsDeepColor36bit, "36-bit"), (hdmi.supportsDeepColor48bit, "48-bit")]
            .filter(\.0).map(\.1)
        return depths.isEmpty ? lm.t("No", "No") : depths.joined(separator: ", ")
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
