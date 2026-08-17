import AppKit
import PDFKit

@MainActor
public enum PDFReportRenderer {
    public enum ExportError: LocalizedError {
        case renderingFailed

        public var errorDescription: String? {
            "Impossibile generare il report PDF."
        }
    }

    public static func write(report: String, to url: URL) throws {
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595, height: 842) // A4 at 72 dpi
        printInfo.leftMargin = 42
        printInfo.rightMargin = 42
        printInfo.topMargin = 42
        printInfo.bottomMargin = 42
        
        let attributedString = formatMarkdown(report)
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        // Print setup
        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin, height: printInfo.paperSize.height - printInfo.topMargin - printInfo.bottomMargin))
        printView.textContainer?.containerSize = NSSize(width: printView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        printView.textContainer?.widthTracksTextView = true
        printView.layoutManager?.replaceTextStorage(textStorage)
        
        let data = NSMutableData()
        let operation = NSPrintOperation.pdfOperation(
            with: printView,
            inside: printView.bounds,
            to: data,
            printInfo: printInfo
        )
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run(), !data.isEmpty else { throw ExportError.renderingFailed }
        try data.write(to: url, options: .atomic)
    }

    private static func formatMarkdown(_ markdown: String) -> NSAttributedString {
        let lines = markdown.components(separatedBy: .newlines)
        let result = NSMutableAttributedString()
        
        let titleFont = NSFont.systemFont(ofSize: 18, weight: .bold)
        let headerFont = NSFont.systemFont(ofSize: 14, weight: .bold)
        let bodyFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let boldBodyFont = NSFont.systemFont(ofSize: 11, weight: .bold)
        
        for line in lines {
            if line.hasPrefix("# ") {
                let text = String(line.dropFirst(2)) + "\n"
                result.append(NSAttributedString(string: text, attributes: [.font: titleFont]))
            } else if line.hasPrefix("## ") {
                let text = "\n" + String(line.dropFirst(3)) + "\n"
                result.append(NSAttributedString(string: text, attributes: [.font: headerFont]))
            } else if line.hasPrefix("### ") {
                let text = "\n" + String(line.dropFirst(4)) + "\n"
                result.append(NSAttributedString(string: text, attributes: [.font: headerFont]))
            } else if line.hasPrefix("- ") {
                let text = String(line) + "\n"
                // parse bold markdown inside the bullet points
                let attrString = NSMutableAttributedString(string: text, attributes: [.font: bodyFont])
                if let regex = try? NSRegularExpression(pattern: "\\*\\*(.*?)\\*\\*") {
                    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
                    for match in matches.reversed() {
                        let range = match.range
                        let innerRange = match.range(at: 1)
                        if let swiftRange = Range(innerRange, in: text) {
                            let boldText = String(text[swiftRange])
                            let rep = NSAttributedString(string: boldText, attributes: [.font: boldBodyFont])
                            attrString.replaceCharacters(in: range, with: rep)
                        }
                    }
                }
                result.append(attrString)
            } else if !line.isEmpty {
                let text = line + "\n"
                result.append(NSAttributedString(string: text, attributes: [.font: bodyFont]))
            }
        }
        
        return result
    }
}
