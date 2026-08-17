import XCTest
import CoreGraphics
@testable import CAVI
import CAVICore

final class CableTestResultCompatibilityTests: XCTestCase {
    func testDecodesHistoryEntryWrittenBeforeCategoryWasIntroduced() throws {
        let legacyJSON = Data("""
        {
          "id": "01234567-89AB-CDEF-0123-456789ABCDEF",
          "cableLabel": "Legacy cable",
          "timestamp": "2025-01-01T12:00:00Z",
          "deviceName": "External SSD",
          "linkSpeedBps": 5000000000
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = try decoder.decode(CableTestResult.self, from: legacyJSON)

        XCTAssertEqual(result.cableLabel, "Legacy cable")
        XCTAssertEqual(result.category, .data)
        XCTAssertNil(result.deviceSerialNumber)
        XCTAssertNil(result.connectionFingerprint)
    }

    @MainActor
    func testRendersAValidPDFDiagnosticReport() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CAVI-Report-\(UUID().uuidString).pdf")
        let keepArtifact = ProcessInfo.processInfo.environment["CAVI_KEEP_PDF_TEST_ARTIFACT"] == "1"
        defer {
            if !keepArtifact {
                try? FileManager.default.removeItem(at: url)
            }
        }

        try PDFReportRenderer.write(report: "# iCollegamenti Report\n\nConnection operating normally.", to: url)

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "%PDF")
        if keepArtifact { print("PDF_TEST_ARTIFACT=\(url.path)") }
    }

    @MainActor
    func testPaginatesLongPDFDiagnosticReport() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CAVI-Long-Report-\(UUID().uuidString).pdf")
        let keepArtifact = ProcessInfo.processInfo.environment["CAVI_KEEP_PDF_TEST_ARTIFACT"] == "1"
        defer {
            if !keepArtifact {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let report = (1...180).map { "\($0). Diagnostic event and measured result." }.joined(separator: "\n")

        try PDFReportRenderer.write(report: report, to: url)

        let document = CGPDFDocument(url as CFURL)
        XCTAssertGreaterThan(document?.numberOfPages ?? 0, 1)
        if keepArtifact { print("PDF_LONG_TEST_ARTIFACT=\(url.path)") }
    }

    @MainActor
    func testShareableDiagnosticReportIncludesEventsAndRedactsConnectionIDs() {
        let store = TestHistoryStore()
        let event = HardwareEvent(
            kind: .linkRenegotiated,
            connectionID: "bsd:disk9",
            displayName: "External SSD",
            linkSpeedBps: 5_000_000_000,
            previousLinkSpeedBps: 10_000_000_000
        )

        let markdown = store.exportMarkdown(language: .english, events: [event])
        XCTAssertTrue(markdown.contains("## Event log"))
        XCTAssertTrue(markdown.contains("## Evidence and limits"))
        XCTAssertTrue(markdown.contains("External SSD"))

        let json = store.exportDiagnosticJSON(events: [event])
        XCTAssertTrue(json.contains("events"))
        XCTAssertFalse(json.contains("bsd:disk9"))
        XCTAssertFalse(json.contains("connectionID"))
    }
}
