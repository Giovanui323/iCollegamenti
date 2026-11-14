import SwiftUI
import CAVICore

struct HDMISignalView: View {
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(HDMIDisplayAnalysisService.self) private var hdmiAnalysis
    @Environment(EDIDReaderService.self) private var edidReader
    @Environment(LanguageManager.self) private var lm

    var body: some View {
        VStack(spacing: 24) {
            if let display = hdmiService.selectedDisplay {
                let config = hdmiAnalysis.currentConfiguration(for: display.displayID)
                let link = HDMILinkReference(edid: edidReader.parsedEDID(for: display.displayID))
                
                heroSection(config: config)
                bandwidthSection(config: config, link: link)
                fallbackSection(config: config)
                explanationSection(config: config, link: link)
            } else {
                Text(lm.t("No display selected", "Nessun display selezionato"))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 600)
    }
    
    @ViewBuilder
    private func heroSection(config: HDMISignalConfiguration?) -> some View {
        GroupBox {
            VStack(spacing: 12) {
                Text("\(config?.width ?? 0) × \(config?.height ?? 0)")
                    .font(.system(size: 36, weight: .bold))
                
                HStack(spacing: 8) {
                    Text("\(String(format: "%.0f", config?.refreshRate ?? 0)) Hz")
                    Text("·")
                    Text("\(config?.bitDepth ?? 8)-bit")
                    Text("·")
                    Text(config?.chroma.description ?? "RGB")
                }
                .font(.title2)
                
                HStack(spacing: 16) {
                    if config?.isHDRActive == true {
                        Label(lm.t("HDR Active", "HDR Attivo"), systemImage: "sun.max.fill")
                            .foregroundStyle(.orange)
                    }
                    if config?.isVRRActive == true {
                        Label(lm.t("VRR Active", "VRR Attivo"), systemImage: "arrow.up.and.down.text.horizontal")
                            .foregroundStyle(.green)
                    }
                }
                .font(.headline)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
    
    @ViewBuilder
    private func bandwidthSection(config: HDMISignalConfiguration?, link: HDMILinkReference) -> some View {
        GroupBox(lm.t("Bandwidth", "Larghezza di Banda")) {
            VStack(alignment: .leading, spacing: 16) {
                let required = config?.bandwidthRequirement.effectiveBandwidthGbps ?? 0
                let headroomPct = link.freeShare(requiredGbps: required)
                
                LabeledContent(lm.t("Required", "Richiesta"), value: String(format: "%.1f Gbps", required))
                // The negotiated cable/port rate cannot be read; prefer the display's own stated limit.
                LabeledContent(
                    link.isStatedByDisplay
                        ? lm.t("Display limit (EDID)", "Limite del monitor (EDID)")
                        : lm.t("HDMI 2.1 maximum (theoretical)", "Massimo HDMI 2.1 (teorico)"),
                    value: String(format: "%.1f Gbps", link.capacityGbps)
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(lm.t("Headroom", "Margine"))
                        Spacer()
                        Text(String(format: "%.0f%%", headroomPct * 100))
                    }
                    
                    ProgressView(value: headroomPct, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(headroomPct > 0.2 ? .green : (headroomPct > 0.05 ? .orange : .red))
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    /// Plain-language reading of the figures above, built from the same values.
    @ViewBuilder
    private func explanationSection(config: HDMISignalConfiguration?, link: HDMILinkReference) -> some View {
        if let config {
            let required = config.bandwidthRequirement.effectiveBandwidthGbps
            let free = Int((link.freeShare(requiredGbps: required) * 100).rounded())
            let capacity = String(format: "%.1f", link.capacityGbps)
            let requiredText = String(format: "%.1f", required)
            let refresh = Int(config.refreshRate.rounded())

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label(lm.t("What these figures mean", "Cosa significano questi dati"), systemImage: "info.circle")
                        .font(.headline)

                    explanationRow(
                        lm.t("Signal", "Segnale"),
                        lm.t(
                            "The Mac sends \(config.width) × \(config.height) pixels, \(refresh) times a second (\(refresh) Hz). \(config.bitDepth)-bit means each colour channel has \(1 << config.bitDepth) shades. \(chromaExplanation(config.chroma, english: true))",
                            "Il Mac invia \(config.width) × \(config.height) pixel, \(refresh) volte al secondo (\(refresh) Hz). \(config.bitDepth) bit significa che ogni canale di colore ha \(1 << config.bitDepth) sfumature. \(chromaExplanation(config.chroma, english: false))"
                        )
                    )
                    explanationRow(
                        lm.t("Required", "Richiesta"),
                        lm.t(
                            "\(requiredText) Gbps is the data this image needs every second, including the HDMI encoding overhead. It is estimated from the mode, not measured on the cable.",
                            "\(requiredText) Gbps sono i dati che questa immagine richiede ogni secondo, compreso il sovraccarico della codifica HDMI. È una stima ricavata dalla modalità, non una misura sul cavo."
                        )
                    )
                    explanationRow(
                        link.isStatedByDisplay ? lm.t("Display limit", "Limite del monitor") : lm.t("Maximum", "Massimo"),
                        link.isStatedByDisplay
                            ? lm.t(
                                "\(capacity) Gbps is the most the monitor says it accepts, read from its EDID. Neither the cable nor the Mac port can be read by macOS, so they could be lower.",
                                "\(capacity) Gbps è il massimo che il monitor dichiara di accettare, letto dal suo EDID. macOS non permette di leggere il limite del cavo né della porta del Mac, che potrebbero essere più bassi."
                            )
                            : lm.t(
                                "This monitor does not state its limit, so the HDMI 2.1 ceiling (\(capacity) Gbps) is shown. Your monitor, cable or port is very likely lower, so the headroom is optimistic.",
                                "Questo monitor non dichiara il proprio limite, quindi viene mostrato il massimo di HDMI 2.1 (\(capacity) Gbps). Monitor, cavo o porta hanno quasi certamente un limite più basso, quindi il margine è ottimistico."
                            )
                    )
                    explanationRow(
                        lm.t("Headroom", "Margine"),
                        lm.t(
                            "\(free)% of that limit is still free. Above 20% the link has room to spare; below 5% the Mac may lower the refresh rate, bit depth or colour sampling to make the image fit.",
                            "Il \(free)% di quel limite resta libero. Sopra il 20% il collegamento ha spazio in abbondanza; sotto il 5% il Mac potrebbe ridurre frequenza, profondità colore o campionamento per far passare l'immagine."
                        )
                    )
                    explanationRow(
                        lm.t("Signal fallback", "Degrado del segnale"),
                        hdmiAnalysis.fallbackDetection?.isFallback == true
                            ? lm.t(
                                "The current resolution is lower than the monitor's native one. Check Displays settings, then try another cable or port.",
                                "La risoluzione attuale è più bassa di quella nativa del monitor. Controlla le impostazioni Monitor, poi prova un altro cavo o porta."
                            )
                            : lm.t(
                                "The monitor runs at its native resolution, so nothing suggests the connection forced a lower mode.",
                                "Il monitor funziona alla sua risoluzione nativa: nulla indica che il collegamento abbia imposto una modalità inferiore."
                            )
                    )
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func explanationRow(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chromaExplanation(_ chroma: ChromaSubsampling, english: Bool) -> String {
        switch chroma {
        case .rgb444, .ycbcr444:
            return english
                ? "\(chroma.rawValue) keeps full colour detail for every pixel, the best quality for text."
                : "\(chroma.rawValue) mantiene il colore completo per ogni pixel: la qualità migliore per il testo."
        case .ycbcr422:
            return english
                ? "\(chroma.rawValue) shares colour between pairs of pixels to save bandwidth; text edges can look slightly soft."
                : "\(chroma.rawValue) condivide il colore tra coppie di pixel per risparmiare banda: i bordi del testo possono apparire un po' sfocati."
        case .ycbcr420:
            return english
                ? "\(chroma.rawValue) shares colour across groups of four pixels to save bandwidth; fine for video, softer for text."
                : "\(chroma.rawValue) condivide il colore tra gruppi di quattro pixel per risparmiare banda: va bene per i video, meno nitido per il testo."
        }
    }

    @ViewBuilder
    private func fallbackSection(config: HDMISignalConfiguration?) -> some View {
        GroupBox {
            if hdmiAnalysis.fallbackDetection?.isFallback == true {
                SemanticStatus(
                    lm.t("Signal fallback detected", "Rilevato degrado del segnale"),
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .warning
                )
            } else {
                SemanticStatus(
                    lm.t("No signal fallback detected", "Nessun degrado del segnale"),
                    systemImage: "checkmark.circle.fill",
                    tone: .success
                )
            }
        }
    }
}
