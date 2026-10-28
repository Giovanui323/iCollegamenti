import XCTest
@testable import CAVICore

/// Builds EDID blobs byte by byte so every field the parser reads is known.
private enum EDIDFixture {
    static let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]

    /// 3840x2160 @ 60 Hz (CTA timing: 594 MHz, 4400 x 2250 total).
    static let uhd60Descriptor: [UInt8] = [
        0x08, 0xE8, 0x00, 0x30, 0xF2, 0x70, 0x5A, 0x80,
        0xB0, 0x58, 0x8A, 0x00, 0x50, 0x1D, 0x74, 0x00, 0x00, 0x1E
    ]

    static func textDescriptor(tag: UInt8, _ text: String) -> [UInt8] {
        var payload = Array(text.utf8.prefix(13))
        if payload.count < 13 { payload.append(0x0A) }
        while payload.count < 13 { payload.append(0x20) }
        return [0x00, 0x00, 0x00, tag, 0x00] + payload
    }

    static func baseBlock(extensionCount: UInt8 = 1) -> [UInt8] {
        var block = header
        block += [0x10, 0xAC] // "DEL"
        block += [0x34, 0x12] // product 0x1234
        block += [0x78, 0x56, 0x34, 0x12] // serial 0x12345678
        block += [12, 30] // week 12, 2020
        block += [1, 4] // EDID 1.4
        block += [0x80 | 0x35, 60, 34, 120, 0x18] // digital, 60x34 cm, gamma 2.2, YCbCr 4:4:4 + 4:2:2
        block += Array(repeating: 0, count: 10) // chromaticity
        block += [0x20, 0x08, 0x80] // established: 640x480@60, 1024x768@60, 1152x870@75
        // Standard timings: 1920x1080@60 (16:9), 1280x1024@60 (5:4), then unused slots.
        block += [0xD1, 0xC0, 0x81, 0x80]
        block += Array(repeating: 0x01, count: 12)
        block += uhd60Descriptor
        block += textDescriptor(tag: 0xFC, "DELL U2720Q")
        block += textDescriptor(tag: 0xFF, "ABC123")
        block += [0x00, 0x00, 0x00, 0x10, 0x00] + Array(repeating: 0, count: 13) // dummy descriptor
        block += [extensionCount, 0x00]
        precondition(block.count == 128)
        return block
    }

    static func dataBlock(tag: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [(tag << 5) | UInt8(payload.count)] + payload
    }

    static var standardDataBlocks: [UInt8] {
        var blocks: [UInt8] = []
        // Video: VIC 16 native (0x90), 97 (4K60), 118 (4K120), 255 (unknown, skipped).
        blocks += dataBlock(tag: 2, [0x90, 97, 118, 0xFF])
        // Audio: LPCM 2 ch 32/44.1/48 kHz 16/20/24-bit, LPCM 8 ch 48/96/192 kHz, AC-3 6 ch.
        blocks += dataBlock(tag: 1, [
            0x09, 0x07, 0x07,
            0x0F, 0x54, 0x07,
            0x15, 0x07, 0x50
        ])
        // Speaker allocation: FL/FR, LFE, FC, RL/RR.
        blocks += dataBlock(tag: 4, [0x0F, 0x00, 0x00])
        // HDMI VSDB: OUI 00-0C-03, PA 1.0.0.0, DC 36 + 30 bit, max TMDS 340 MHz.
        blocks += dataBlock(tag: 3, [0x03, 0x0C, 0x00, 0x10, 0x00, 0x30, 68])
        // HDMI Forum VSDB: OUI C4-5D-D8, version 1, max TMDS 600 MHz, 4:2:0 10-bit, VRR 48–120 Hz.
        blocks += dataBlock(tag: 3, [0xD8, 0x5D, 0xC4, 0x01, 120, 0x00, 0x01, 0x00, 0x00, 48, 120])
        // HDR static metadata: SDR + PQ + HLG, max 1000 cd/m² (code 160), max FALL 400 (code 118), min code 0.
        blocks += dataBlock(tag: 7, [6, 0x0D, 0x01, 160, 118, 0])
        // Colorimetry: BT2020RGB + BT2020YCC, DCI-P3.
        blocks += dataBlock(tag: 7, [5, 0xC0, 0x80])
        // A zero-length vendor block must be skipped, not trap.
        blocks += [0x60]
        // YCbCr 4:2:0 video data block with VIC 97.
        blocks += dataBlock(tag: 7, [14, 97])
        return blocks
    }

    static func ctaBlock(dataBlocks: [UInt8] = standardDataBlocks) -> [UInt8] {
        let dtdOffset = UInt8(4 + dataBlocks.count)
        var block: [UInt8] = [0x02, 0x03, dtdOffset, 0x70]
        block += dataBlocks
        block += Array(repeating: 0, count: 128 - block.count)
        return block
    }

    static var fullEDID: [UInt8] { baseBlock() + ctaBlock() }
}

final class EDIDParserTests: XCTestCase {
    func testRejectsShortInputAndInvalidHeader() {
        XCTAssertNil(EDIDParser.parse([]))
        XCTAssertNil(EDIDParser.parse(Array(EDIDFixture.fullEDID.prefix(127))))
        var broken = EDIDFixture.baseBlock()
        broken[0] = 0x01
        XCTAssertNil(EDIDParser.parse(broken))
    }

    func testDecodesIdentityFromBaseBlock() throws {
        let edid = try XCTUnwrap(EDIDParser.parse(EDIDFixture.baseBlock(extensionCount: 0)))

        XCTAssertEqual(edid.manufacturerCode, "DEL")
        XCTAssertEqual(edid.manufacturerName, "Dell")
        XCTAssertEqual(edid.productID, 0x1234)
        XCTAssertEqual(edid.serialNumber, 0x1234_5678)
        XCTAssertEqual(edid.manufactureWeek, 12)
        XCTAssertEqual(edid.manufactureYear, 2020)
        XCTAssertEqual(edid.edidVersion, "1.4")
        XCTAssertTrue(edid.isDigital)
        XCTAssertEqual(edid.screenWidthCm, 60)
        XCTAssertEqual(edid.screenHeightCm, 34)
        XCTAssertEqual(try XCTUnwrap(edid.gamma), 2.2, accuracy: 0.001)
        XCTAssertTrue(edid.supportsYCbCr444)
        XCTAssertTrue(edid.supportsYCbCr422)
        XCTAssertEqual(edid.manufactureName, "DELL U2720Q")
        XCTAssertEqual(edid.serialString, "ABC123")
        XCTAssertNil(edid.ctaExtension)
    }

    func testDetailedTimingGivesNativeResolutionAndRefresh() throws {
        let edid = try XCTUnwrap(EDIDParser.parse(EDIDFixture.baseBlock(extensionCount: 0)))
        let timing = try XCTUnwrap(edid.detailedTimings.first)

        XCTAssertEqual(edid.detailedTimings.count, 1, "Display descriptors are not timings")
        XCTAssertEqual(timing.pixelClockKHz, 594_000)
        XCTAssertEqual(timing.hTotal, 4400)
        XCTAssertEqual(timing.vTotal, 2250)
        XCTAssertEqual(timing.refreshRate, 60, accuracy: 0.01)
        XCTAssertFalse(timing.isInterlaced)
        XCTAssertEqual(edid.nativeResolution, EDIDResolution(width: 3840, height: 2160))
    }

    func testStandardTimingsHaveAHeightAndSkipUnusedSlots() throws {
        let edid = try XCTUnwrap(EDIDParser.parse(EDIDFixture.baseBlock(extensionCount: 0)))

        XCTAssertEqual(edid.standardTimings, [
            EDIDStandardTiming(width: 1920, height: 1080, refreshRate: 60, aspectRatio: "16:9"),
            EDIDStandardTiming(width: 1280, height: 1024, refreshRate: 60, aspectRatio: "5:4")
        ])
    }

    func testEstablishedTimingsAreDecoded() throws {
        let edid = try XCTUnwrap(EDIDParser.parse(EDIDFixture.baseBlock(extensionCount: 0)))
        XCTAssertEqual(edid.establishedTimings, ["640x480@60Hz", "1024x768@60Hz", "1152x870@75Hz"])
    }

    func testMalformedDetailedTimingDoesNotProduceNaN() throws {
        var block = EDIDFixture.baseBlock(extensionCount: 0)
        // Non-zero pixel clock, but every active/blanking field zero.
        for index in 56..<72 { block[index] = 0 }
        let edid = try XCTUnwrap(EDIDParser.parse(block))
        let timing = try XCTUnwrap(edid.detailedTimings.first)
        XCTAssertTrue(timing.refreshRate.isFinite)
        XCTAssertEqual(timing.refreshRate, 0)
    }

    func testParsesCTAVideoModes() throws {
        let cta = try XCTUnwrap(EDIDParser.parse(EDIDFixture.fullEDID)?.ctaExtension)

        XCTAssertEqual(cta.revision, 3)
        XCTAssertTrue(cta.supportsYCbCr444)
        XCTAssertTrue(cta.supportsYCbCr422)
        XCTAssertEqual(cta.supportedVideoModes.map(\.vic), [16, 97, 118, 97], "Unknown VIC 255 is skipped")
        let native = try XCTUnwrap(cta.supportedVideoModes.first)
        XCTAssertTrue(native.isNative)
        XCTAssertEqual(native.width, 1920)
        XCTAssertEqual(native.height, 1080)
        XCTAssertTrue(cta.supportedVideoModes.contains { $0.width == 3840 && $0.refreshRate == 120 })
        XCTAssertTrue(cta.supportsYCbCr420)
    }

    func testParsesCTAAudioAndSpeakers() throws {
        let cta = try XCTUnwrap(EDIDParser.parse(EDIDFixture.fullEDID)?.ctaExtension)

        XCTAssertEqual(cta.audioFormats.count, 3)
        XCTAssertEqual(cta.audioFormats[0].formatName, "LPCM")
        XCTAssertEqual(cta.audioFormats[0].maxChannels, 2)
        XCTAssertEqual(cta.audioFormats[0].sampleRates, [32000, 44100, 48000])
        XCTAssertEqual(cta.audioFormats[0].bitDepths, [16, 20, 24])
        XCTAssertEqual(cta.audioFormats[1].maxChannels, 8)
        XCTAssertEqual(cta.audioFormats[1].sampleRates, [48000, 96000, 192000])
        XCTAssertEqual(cta.audioFormats[2].formatName, "AC-3")
        XCTAssertNil(cta.audioFormats[2].bitDepths)

        let speakers = try XCTUnwrap(cta.speakerAllocation)
        XCTAssertTrue(speakers.frontLeftRight)
        XCTAssertTrue(speakers.lfe)
        XCTAssertTrue(speakers.frontCenter)
        XCTAssertTrue(speakers.rearLeftRight)
        XCTAssertFalse(speakers.topChannels)
        XCTAssertEqual(speakers.channelDescription, "FL/FR, LFE, FC, RL/RR")
    }

    func testParsesHDMIVendorBlocks() throws {
        let cta = try XCTUnwrap(EDIDParser.parse(EDIDFixture.fullEDID)?.ctaExtension)
        let hdmi = try XCTUnwrap(cta.hdmiVendorBlock)

        XCTAssertEqual(hdmi.maxTMDSClockMHz, 600, "HDMI Forum block raises the 340 MHz HDMI 1.4 limit")
        XCTAssertTrue(hdmi.supportsDeepColor30bit)
        XCTAssertTrue(hdmi.supportsDeepColor36bit)
        XCTAssertFalse(hdmi.supportsDeepColor48bit)
        XCTAssertFalse(hdmi.supportsAI)
        XCTAssertEqual(cta.vrrRange, VRRRange(minRefreshHz: 48, maxRefreshHz: 120, supportsAdaptiveSync: true))
    }

    func testParsesHDRAndColorimetry() throws {
        let cta = try XCTUnwrap(EDIDParser.parse(EDIDFixture.fullEDID)?.ctaExtension)
        let hdr = try XCTUnwrap(cta.hdrCapabilities)

        XCTAssertTrue(hdr.supportsSDR)
        XCTAssertTrue(hdr.supportsHDR)
        XCTAssertTrue(hdr.supportsSMPTE_ST_2084)
        XCTAssertTrue(hdr.supportsHLG)
        XCTAssertEqual(try XCTUnwrap(hdr.maxLuminanceCdm2), 1600, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(hdr.maxFrameAverageLuminance), 50 * pow(2, 118.0 / 32), accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(hdr.minLuminanceCdm2), 0, accuracy: 0.0001)
        XCTAssertEqual(cta.colorimetry, ["BT2020YCC", "BT2020RGB", "DCI-P3"])
    }

    func testRawBlocksKeepZeroLengthBlocksWithoutCrashing() throws {
        let cta = try XCTUnwrap(EDIDParser.parse(EDIDFixture.fullEDID)?.ctaExtension)
        let empty = try XCTUnwrap(cta.rawDataBlocks.first { $0.length == 0 })
        XCTAssertEqual(empty.rawBytes, [])
        XCTAssertEqual(cta.rawDataBlocks.count, 9)
    }

    func testTruncatedDataBlockStopsParsingSafely() throws {
        // A block claiming 31 bytes near the end of the extension must not read past it.
        var extensionBlock = EDIDFixture.ctaBlock(dataBlocks: [])
        extensionBlock[2] = 0
        extensionBlock[120] = (2 << 5) | 31
        extensionBlock[4] = (7 << 5) // zero-length extended block
        let edid = try XCTUnwrap(EDIDParser.parse(EDIDFixture.baseBlock() + extensionBlock))
        XCTAssertNotNil(edid.ctaExtension)
    }

    func testFindsCTABlockAfterAnotherExtension() throws {
        var blockMap = [UInt8](repeating: 0, count: 128)
        blockMap[0] = 0xF0
        let edid = try XCTUnwrap(EDIDParser.parse(EDIDFixture.baseBlock(extensionCount: 2) + blockMap + EDIDFixture.ctaBlock()))
        XCTAssertEqual(edid.ctaExtension?.supportedVideoModes.count, 4)
    }

    func testExtensionCountLargerThanDataIsIgnored() throws {
        let edid = try XCTUnwrap(EDIDParser.parse(EDIDFixture.baseBlock(extensionCount: 3)))
        XCTAssertNil(edid.ctaExtension)
        XCTAssertEqual(edid.extensionCount, 3)
    }
}
