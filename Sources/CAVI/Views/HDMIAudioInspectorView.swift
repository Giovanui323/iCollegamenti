import SwiftUI
import CAVICore

struct HDMIAudioInspectorView: View {
    @Environment(EDIDReaderService.self) private var edidReader
    @Environment(HDMIDisplayDiscoveryService.self) private var hdmiService
    @Environment(LanguageManager.self) private var lm

    var body: some View {
        VStack(spacing: 24) {
            if let display = hdmiService.selectedDisplay,
               let edid = edidReader.parsedEDID(for: display.displayID) {
                
                let audioFormats = edid.ctaExtension?.audioFormats ?? []
                let speakerAllocs: [CAVICore.CTASpeakerAllocation] = edid.ctaExtension?.speakerAllocation != nil ? [edid.ctaExtension!.speakerAllocation!] : []
                
                if audioFormats.isEmpty {
                    ContentUnavailableView(
                        lm.t("No Audio Supported", "Nessun Audio Supportato"),
                        systemImage: "speaker.slash"
                    )
                } else {
                    GroupBox(lm.t("Supported Audio Formats", "Formati Audio Supportati")) {
                        List(audioFormats, id: \.formatName) { format in
                            HStack {
                                Text(format.formatName).frame(width: 100, alignment: .leading)
                                Text("\(format.maxChannels) ch").frame(width: 80, alignment: .leading)
                                Text(format.sampleRates.map { "\($0)kHz" }.joined(separator: ", ")).frame(width: 150, alignment: .leading)
                                Text(format.bitDepths?.map { "\($0)-bit" }.joined(separator: ", ") ?? "").frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(minHeight: 200)
                    }
                    
                    if !speakerAllocs.isEmpty {
                        GroupBox(lm.t("Speaker Allocation", "Configurazione Altoparlanti")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(speakerAllocs, id: \.channelDescription) { alloc in
                                    HStack {
                                        Image(systemName: "speaker.wave.3.fill")
                                            .foregroundStyle(.blue)
                                        Text(alloc.channelDescription)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                        }
                    }
                }
                
            } else {
                Text(lm.t("No display selected", "Nessun display selezionato"))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
