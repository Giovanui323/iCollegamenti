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
        VStack(alignment: .leading, spacing: 16) {
            if !edid.isChecksumValid {
                SemanticStatus(
                    lm.t("The EDID checksum is wrong. The data below may be corrupted by the cable, adapter or display.",
                         "Il checksum dell'EDID è errato. I dati qui sotto potrebbero essere corrotti da cavo, adattatore o monitor."),
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .warning
                )
            }

            summaryHeader(edid: edid)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                InfoCard(title: lm.t("Manufacturer", "Produttore"), systemImage: "building.2") {
                    InfoRow(lm.t("Brand", "Marca"), edid.manufacturerName ?? edid.manufacturerCode)
                    if let model = edid.manufactureName { InfoRow(lm.t("Model", "Modello"), model) }
                    InfoRow(lm.t("Product code", "Codice prodotto"), String(format: "0x%04X", edid.productCode))
                    if let serial = edid.serialString { InfoRow(lm.t("Serial", "Seriale"), serial) }
                    InfoRow(lm.t("Manufactured", "Fabbricazione"), edid.manufactureWeek > 0 && edid.manufactureWeek <= 53
                        ? lm.t("Week \(edid.manufactureWeek), \(edid.manufactureYear)", "Settimana \(edid.manufactureWeek), \(edid.manufactureYear)")
                        : "\(edid.manufactureYear)")
                    InfoRow(lm.t("EDID version", "Versione EDID"), edid.edidVersion)
                    InfoFlagRow("Checksum", edid.isChecksumValid, yes: lm.t("Valid", "Valido"), no: lm.t("Invalid", "Non valido"))
                }

                InfoCard(title: lm.t("Panel", "Pannello"), systemImage: "display") {
                    if let timing = edid.detailedTimings.first {
                        InfoRow(lm.t("Native mode", "Modalità nativa"), String(format: "%d × %d @ %.2f Hz", timing.hActive, timing.vActive, timing.refreshRate))
                        InfoRow(lm.t("Pixel clock", "Pixel clock"), String(format: "%.2f MHz", Double(timing.pixelClockKHz) / 1_000))
                    }
                    InfoRow(lm.t("Physical size", "Dimensioni fisiche"), "\(edid.screenWidthCm) × \(edid.screenHeightCm) cm" + diagonal(edid))
                    InfoRow(lm.t("Gamma", "Gamma"), edid.gamma.map { String(format: "%.2f", $0) } ?? "—")
                    InfoRow(lm.t("Colour formats", "Formati colore"), colourFormats(edid))
                    if let colorimetry = edid.ctaExtension?.colorimetry, !colorimetry.isEmpty {
                        InfoRow(lm.t("Colorimetry", "Colorimetria"), colorimetry.joined(separator: ", "))
                    }
                }

                InfoCard(title: lm.t("HDMI interface", "Interfaccia HDMI"), systemImage: "cable.connector.horizontal") {
                    if let hdmi = edid.ctaExtension?.hdmiVendorBlock {
                        InfoRow(lm.t("Max TMDS clock", "Clock TMDS max"), hdmi.maxTMDSClockMHz.map { "\($0) MHz" } ?? "—")
                        if let frl = hdmi.maxFRLRateGbps {
                            InfoRow(lm.t("Max FRL rate (HDMI 2.1)", "Velocità FRL max (HDMI 2.1)"), "\(frl) Gb/s")
                        }
                        InfoRow(lm.t("Deep colour", "Deep color"), deepColour(hdmi))
                        InfoFlagRow("3D", hdmi.supports3D, yes: lm.t("Yes", "Sì"), no: lm.t("No", "No"))
                    } else {
                        Text(lm.t("No HDMI block in the EDID: the monitor may be DisplayPort-only or limited to basic HDMI.",
                                  "Nessun blocco HDMI nell'EDID: il monitor potrebbe essere solo DisplayPort o limitato all'HDMI di base."))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let capacity = edid.advertisedLinkCapacityGbps {
                        InfoRow(lm.t("Stated link capacity", "Capacità link dichiarata"), String(format: "%.1f Gb/s", capacity), emphasized: true)
                    }
                }

                InfoCard(title: lm.t("HDR & variable refresh", "HDR e refresh variabile"), systemImage: "sun.max") {
                    let hdr = edid.ctaExtension?.hdrCapabilities
                    InfoFlagRow("HDR10 (PQ)", hdr?.supportsSMPTE_ST_2084 == true, yes: lm.t("Supported", "Supportato"), no: lm.t("Not stated", "Non dichiarato"))
                    InfoFlagRow("HLG", hdr?.supportsHLG == true, yes: lm.t("Supported", "Supportato"), no: lm.t("Not stated", "Non dichiarato"))
                    if let maxLuminance = hdr?.maxLuminanceCdm2 {
                        InfoRow(lm.t("Peak luminance", "Luminanza di picco"), String(format: "%.0f cd/m²", maxLuminance))
                    }
                    if let average = hdr?.maxFrameAverageLuminance {
                        InfoRow(lm.t("Max frame average", "Media max fotogramma"), String(format: "%.0f cd/m²", average))
                    }
                    if let minimum = hdr?.minLuminanceCdm2 {
                        InfoRow(lm.t("Minimum luminance", "Luminanza minima"), String(format: "%.4f cd/m²", minimum))
                    }
                    if let vrr = edid.ctaExtension?.vrrRange {
                        InfoRow("VRR", "\(vrr.minRefreshHz)–\(vrr.maxRefreshHz) Hz", emphasized: true)
                    } else {
                        InfoFlagRow("VRR", false, yes: "", no: lm.t("Not stated", "Non dichiarato"))
                    }
                }
            }

            let modes = edid.advertisedModes
            if !modes.isEmpty {
                InfoCard(title: lm.t("Advertised video modes (\(modes.count))", "Modalità video dichiarate (\(modes.count))"), systemImage: "rectangle.3.group") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(modes) { mode in
                            HStack(spacing: 6) {
                                Text("\(mode.width)×\(mode.height)")
                                    .fontWeight(.medium)
                                Text(String(format: "%.0f Hz", mode.refreshRate))
                                    .foregroundStyle(.secondary)
                                if mode.isNative {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.yellow)
                                        .help(lm.t("Native mode", "Modalità nativa"))
                                }
                            }
                            .font(.callout.monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(mode.isNative ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1))
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One-line identity of the monitor above the cards.
    private func summaryHeader(edid: CAVICore.ParsedEDID) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "display")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text([edid.manufacturerName, edid.manufactureName].compactMap { $0 }.joined(separator: " "))
                    .font(.title2.weight(.semibold))
                Text(summaryLine(edid))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func summaryLine(_ edid: CAVICore.ParsedEDID) -> String {
        var parts: [String] = []
        if let native = edid.nativeResolution { parts.append("\(native.width) × \(native.height)") }
        if let maxRefresh = edid.advertisedModes.map(\.refreshRate).max() { parts.append(String(format: "%.0f Hz max", maxRefresh)) }
        if edid.supportsHDR10 { parts.append("HDR10") }
        if edid.ctaExtension?.vrrRange != nil { parts.append("VRR") }
        parts.append("EDID \(edid.edidVersion)")
        return parts.joined(separator: " · ")
    }

    private func diagonal(_ edid: CAVICore.ParsedEDID) -> String {
        guard edid.screenWidthCm > 0, edid.screenHeightCm > 0 else { return "" }
        let inches = (Double(edid.screenWidthCm * edid.screenWidthCm + edid.screenHeightCm * edid.screenHeightCm)).squareRoot() / 2.54
        return String(format: " (≈ %.0f\")", inches)
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

/// A titled card that fills its grid cell.
private struct InfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
    }
}

/// Label on the left, value aligned on the right.
private struct InfoRow: View {
    let label: String
    let value: String
    var emphasized = false

    init(_ label: String, _ value: String, emphasized: Bool = false) {
        self.label = label
        self.value = value
        self.emphasized = emphasized
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(emphasized ? .semibold : .regular)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

/// A yes/no value shown as a coloured indicator.
private struct InfoFlagRow: View {
    let label: String
    let isOn: Bool
    let yes: String
    let no: String

    init(_ label: String, _ isOn: Bool, yes: String, no: String) {
        self.label = label
        self.isOn = isOn
        self.yes = yes
        self.no = no
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Label(isOn ? yes : no, systemImage: isOn ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isOn ? Color.green : Color.secondary)
        }
        .font(.callout)
    }
}
