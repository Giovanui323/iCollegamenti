import SwiftUI
import CAVICore

struct BenchmarkLinkExpectationView: View {
    let linkSpeedBps: UInt64?
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        if let expectation = BenchmarkLinkExpectation.usefulSequentialRange(linkSpeedBps: linkSpeedBps) {
            GroupBox(languageManager.t("Expected Link Speeds", "Velocità attese del collegamento")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(languageManager.t("Expected Real-World Speed", "Velocità reale attesa del canale"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(expectation.realisticRangeFormatted)
                                .font(.headline.weight(.semibold))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(languageManager.t("Theoretical Link Max", "Max teorico link"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(expectation.theoreticalMaxFormatted) (\(expectation.protocolName))")
                                .font(.subheadline)
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(languageManager.t("Typical speeds by drive type on this link:", "Velocità tipiche per tipo di unità su questo link:"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                            GridRow {
                                Text("• SSD NVMe / SSD veloce:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("fino a \(Int(expectation.realisticMaximumMBps)) MB/s (\(languageManager.t("saturates link", "satura il link")))")
                                    .font(.caption.weight(.medium))
                            }
                            if expectation.realisticMaximumMBps > 550 {
                                GridRow {
                                    Text("• SSD SATA esterno:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("450 – 550 MB/s (\(languageManager.t("SATA limit", "limite SATA")))")
                                        .font(.caption.weight(.medium))
                                }
                            }
                            GridRow {
                                Text("• \(languageManager.t("USB Flash Drive / Pen Drive", "Chiavetta USB standard")):")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(languageManager.t(
                                    "Read: 100–\(Int(min(450, expectation.realisticMaximumMBps))) MB/s • Write: 20–150 MB/s",
                                    "Lettura: 100–\(Int(min(450, expectation.realisticMaximumMBps))) MB/s • Scrittura: 20–150 MB/s"
                                ))
                                    .font(.caption.weight(.medium))
                            }
                            GridRow {
                                Text("• \(languageManager.t("Mechanical Hard Disk (HDD)", "Hard Disk meccanico (HDD)")):")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("80 – 180 MB/s")
                                    .font(.caption.weight(.medium))
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
