import AppKit
import CoreText

@MainActor
public enum PDFReportRenderer {
    public enum ExportError: LocalizedError {
        case renderingFailed

        public var errorDescription: String? {
            "Impossibile generare il report PDF."
        }
    }

    /// A4 at 72 dpi with 42 pt margins. Text is laid out with CoreText and split
    /// across as many pages as needed, so long reports are never truncated.
    public static func write(report: String, to url: URL) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let textRect = pageRect.insetBy(dx: 42, dy: 42)

        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw ExportError.renderingFailed }

        let attributedString = formatMarkdown(report)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let totalLength = attributedString.length
        var location = 0

        repeat {
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )
            let visibleLength = CTFrameGetVisibleStringRange(frame).length
            // A zero-length page means the text can no longer fit; stop instead of looping forever.
            guard visibleLength > 0 else { break }

            context.beginPDFPage(nil)
            CTFrameDraw(frame, context)
            context.endPDFPage()
            location += visibleLength
        } while location < totalLength

        guard location > 0 else { throw ExportError.renderingFailed }
        context.closePDF()
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
