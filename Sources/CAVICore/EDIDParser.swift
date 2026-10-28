import Foundation

public struct ParsedEDID: Codable, Hashable, Sendable {
    public let manufacturerCode: String
    public let manufacturerName: String?
    public let productID: UInt16
    public let serialNumber: UInt32
    public let serialString: String?
    public let manufactureName: String?
    public let manufactureWeek: Int
    public let manufactureYear: Int
    public let edidVersion: String
    public let isDigital: Bool
    public let screenWidthCm: Int
    public let screenHeightCm: Int
    public let gamma: Double?
    
    public let supportsRGB444: Bool
    public let supportsYCbCr444: Bool  
    public let supportsYCbCr422: Bool
    
    public let nativeResolution: EDIDResolution?
    public let detailedTimings: [EDIDDetailedTiming]
    public let standardTimings: [EDIDStandardTiming]
    public let establishedTimings: [String]
    
    public let ctaExtension: CTAExtension?
    
    public let rawBytes: [UInt8]
    public let extensionCount: Int
    
    public var productCode: UInt16 { productID }
    public var rawHexDump: String {
        rawBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

public struct EDIDResolution: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
}

public struct EDIDDetailedTiming: Codable, Hashable, Sendable {
    public let pixelClockKHz: Int
    public let hActive: Int
    public let hBlanking: Int
    public let hTotal: Int
    public let vActive: Int
    public let vBlanking: Int  
    public let vTotal: Int
    public let refreshRate: Double
    public let isInterlaced: Bool
}

public struct EDIDStandardTiming: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let refreshRate: Int
    public let aspectRatio: String
}

public struct CTAExtension: Codable, Hashable, Sendable {
    public let revision: Int
    public let supportsYCbCr444: Bool
    public let supportsYCbCr422: Bool
    public let supportsYCbCr420: Bool
    
    public let supportedVideoModes: [CTAVideoMode]
    
    public let audioFormats: [CTAAudioFormat]
    public let speakerAllocation: CTASpeakerAllocation?
    
    public let hdmiVendorBlock: HDMIVendorBlock?
    
    public let hdrCapabilities: HDRCapabilities?
    
    public let vrrRange: VRRRange?
    
    public let colorimetry: [String]
    
    public let rawDataBlocks: [CTARawDataBlock]
}

public struct CTAVideoMode: Codable, Hashable, Sendable {
    public let vic: Int
    public let width: Int
    public let height: Int
    public let refreshRate: Double
    public let isInterlaced: Bool
    public let isNative: Bool
    public let aspectRatio: String
}

public struct CTAAudioFormat: Codable, Hashable, Sendable {
    public let formatName: String
    public let maxChannels: Int
    public let sampleRates: [Int]
    public let bitDepths: [Int]?
    public let maxBitrate: Int?
}

public struct CTASpeakerAllocation: Codable, Hashable, Sendable {
    public let frontLeftRight: Bool
    public let lfe: Bool
    public let frontCenter: Bool
    public let rearLeftRight: Bool
    public let rearCenter: Bool
    public let frontLeftRightCenter: Bool
    public let rearLeftRightCenter: Bool
    public let topChannels: Bool
    public let channelDescription: String
}

public struct HDMIVendorBlock: Codable, Hashable, Sendable {
    public let maxTMDSClockMHz: Int?
    public let supports3D: Bool
    public let supportsDeepColor30bit: Bool
    public let supportsDeepColor36bit: Bool
    public let supportsDeepColor48bit: Bool
    public let supportsAI: Bool
    /// Fixed Rate Link capacity advertised in the HDMI Forum block (HDMI 2.1), in Gb/s.
    public var maxFRLRateGbps: Int? = nil
}

public struct HDRCapabilities: Codable, Hashable, Sendable {
    public let supportsSDR: Bool
    public let supportsHDR: Bool
    public let supportsSMPTE_ST_2084: Bool
    public let supportsHLG: Bool
    public let maxLuminanceCdm2: Double?
    public let minLuminanceCdm2: Double?
    public let maxFrameAverageLuminance: Double?
}

public struct VRRRange: Codable, Hashable, Sendable {
    public let minRefreshHz: Int
    public let maxRefreshHz: Int
    public let supportsAdaptiveSync: Bool
    
    public var minRefreshRate: Int { minRefreshHz }
    public var maxRefreshRate: Int { maxRefreshHz }
}

public struct CTARawDataBlock: Codable, Hashable, Sendable {
    public let tagCode: Int
    public let extendedTagCode: Int?
    public let blockName: String
    public let length: Int
    public let rawBytes: [UInt8]
}

public enum EDIDParser {
    public static func parse(_ data: [UInt8]) -> ParsedEDID? {
        guard data.count >= 128 else { return nil }
        
        let header = Array(data[0...7])
        if header != [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00] { return nil }
        
        let mfg1 = (data[8] >> 2) & 0x1F
        let mfg2 = ((data[8] & 0x03) << 3) | ((data[9] >> 5) & 0x07)
        let mfg3 = data[9] & 0x1F
        
        func toAscii(_ val: UInt8) -> String {
            if val > 0 && val <= 26 {
                return String(Character(UnicodeScalar(val + 64)))
            }
            return ""
        }
        
        let manufacturerCode = toAscii(mfg1) + toAscii(mfg2) + toAscii(mfg3)
        let manufacturerName = manufacturerNameFromCode(manufacturerCode)
        
        let productID = UInt16(data[10]) | (UInt16(data[11]) << 8)
        let serialNumber = UInt32(data[12]) | (UInt32(data[13]) << 8) | (UInt32(data[14]) << 16) | (UInt32(data[15]) << 24)
        
        let week = Int(data[16])
        let year = Int(data[17]) + 1990
        
        let version = "\(data[18]).\(data[19])"
        let isDigital = (data[20] & 0x80) != 0
        
        let widthCm = Int(data[21])
        let heightCm = Int(data[22])
        let gamma = data[23] != 0xFF ? (Double(data[23]) / 100.0) + 1.0 : nil
        
        let features = data[24]
        let ycbcrSupport = (features >> 3) & 0x03
        let supportsYCbCr422 = isDigital && (ycbcrSupport == 1 || ycbcrSupport == 3)
        let supportsYCbCr444 = isDigital && (ycbcrSupport == 2 || ycbcrSupport == 3)
        let supportsRGB444 = true
        
        // Standard Timings (bytes 38-53)
        var standardTimings: [EDIDStandardTiming] = []
        for i in stride(from: 38, to: 54, by: 2) {
            let byte0 = data[i]
            let byte1 = data[i+1]
            if byte0 != 0x00 && !(byte0 == 0x01 && byte1 == 0x01) {
                let width = (Int(byte0) + 31) * 8
                let aspectRaw = (byte1 >> 6) & 0x03
                let aspect: String
                let height: Int
                switch aspectRaw {
                case 0: aspect = "16:10"; height = width * 10 / 16
                case 1: aspect = "4:3"; height = width * 3 / 4
                case 2: aspect = "5:4"; height = width * 4 / 5
                default: aspect = "16:9"; height = width * 9 / 16
                }
                let refresh = Int(byte1 & 0x3F) + 60
                standardTimings.append(EDIDStandardTiming(width: width, height: height, refreshRate: refresh, aspectRatio: aspect))
            }
        }
        
        var detailedTimings: [EDIDDetailedTiming] = []
        var serialString: String? = nil
        var manufactureName: String? = nil
        
        // Detailed Timings (4 blocks of 18 bytes starting at 54)
        for i in stride(from: 54, to: 126, by: 18) {
            let pixelClockRaw = UInt16(data[i]) | (UInt16(data[i+1]) << 8)
            if pixelClockRaw != 0 {
                let pixelClockHz = Int(pixelClockRaw) * 10_000
                let hActive = Int(data[i+2]) | ((Int(data[i+4]) >> 4) << 8)
                let hBlanking = Int(data[i+3]) | ((Int(data[i+4]) & 0x0F) << 8)
                let vActive = Int(data[i+5]) | ((Int(data[i+7]) >> 4) << 8)
                let vBlanking = Int(data[i+6]) | ((Int(data[i+7]) & 0x0F) << 8)
                let hTotal = hActive + hBlanking
                let vTotal = vActive + vBlanking
                let isInterlaced = (data[i+17] & 0x80) != 0
                let refreshRate = hTotal > 0 && vTotal > 0 ? Double(pixelClockHz) / Double(hTotal * vTotal) : 0
                
                detailedTimings.append(EDIDDetailedTiming(
                    pixelClockKHz: pixelClockHz / 1000,
                    hActive: hActive,
                    hBlanking: hBlanking,
                    hTotal: hTotal,
                    vActive: vActive,
                    vBlanking: vBlanking,
                    vTotal: vTotal,
                    refreshRate: refreshRate,
                    isInterlaced: isInterlaced
                ))
            } else {
                let tag = data[i+3]
                if tag == 0xFC {
                    // Monitor Name
                    manufactureName = descriptorString(data[(i+5)...(i+17)])
                } else if tag == 0xFF {
                    // Serial String
                    serialString = descriptorString(data[(i+5)...(i+17)])
                }
            }
        }
        
        let nativeResolution = detailedTimings.first.map { EDIDResolution(width: $0.hActive, height: $0.vActive) }
        
        let extensionCount = Int(data[126])
        var ctaExtension: CTAExtension? = nil
        
        let availableExtensions = min(extensionCount, data.count / 128 - 1)
        let ctaBlockStart = availableExtensions > 0
            ? (1...availableExtensions).map { $0 * 128 }.first { data[$0] == 0x02 }
            : nil
        if let ctaBlockStart {
            let extData = Array(data[ctaBlockStart..<(ctaBlockStart + 128)])
            do { // CTA Tag
                let revision = Int(extData[1])
                let dtdOffset = Int(extData[2])
                let ycbcrFlags = extData[3]
                let ctaSupportsYCbCr444 = (ycbcrFlags & 0x20) != 0
                let ctaSupportsYCbCr422 = (ycbcrFlags & 0x10) != 0
                
                var rawDataBlocks: [CTARawDataBlock] = []
                var audioFormats: [CTAAudioFormat] = []
                var speakerAllocation: CTASpeakerAllocation? = nil
                var videoModes: [CTAVideoMode] = []
                var hdmiVendorBlock: HDMIVendorBlock? = nil
                var hdrCapabilities: HDRCapabilities? = nil
                var vrrRange: VRRRange? = nil
                var colorimetry: [String] = []
                var supportsYCbCr420 = false
                var forumMaxTMDSClockMHz: Int? = nil
                var forumMaxFRLRateGbps: Int? = nil
                
                var idx = 4
                let endIdx = (dtdOffset > 4 && dtdOffset <= 127) ? dtdOffset : extData.count
                while idx < endIdx {
                    let header = extData[idx]
                    let tagCode = Int(header >> 5)
                    let length = Int(header & 0x1F)
                    
                    if idx + 1 + length > extData.count { break }
                    // A zero-length block is legal; slicing (idx+1)...idx would trap.
                    let blockBytes = length > 0 ? Array(extData[(idx+1)...(idx+length)]) : []
                    
                    var extendedTagCode: Int? = nil
                    var blockName = "Unknown Block"
                    
                    if tagCode == 1 { // Audio
                        blockName = "Audio Data Block"
                        for b in stride(from: 0, to: length, by: 3) {
                            if b + 2 < blockBytes.count {
                                let fmt = Int(blockBytes[b] >> 3) & 0x0F
                                let maxChannels = (Int(blockBytes[b] & 0x07)) + 1
                                let sampleRateBits = Int(blockBytes[b+1])
                                var sampleRates: [Int] = []
                                if (sampleRateBits & 0x01) != 0 { sampleRates.append(32000) }
                                if (sampleRateBits & 0x02) != 0 { sampleRates.append(44100) }
                                if (sampleRateBits & 0x04) != 0 { sampleRates.append(48000) }
                                if (sampleRateBits & 0x08) != 0 { sampleRates.append(88200) }
                                if (sampleRateBits & 0x10) != 0 { sampleRates.append(96000) }
                                if (sampleRateBits & 0x20) != 0 { sampleRates.append(176400) }
                                if (sampleRateBits & 0x40) != 0 { sampleRates.append(192000) }
                                
                                var bitDepths: [Int]? = nil
                                if fmt == 1 {
                                    let bdBits = Int(blockBytes[b+2])
                                    var bds: [Int] = []
                                    if (bdBits & 0x01) != 0 { bds.append(16) }
                                    if (bdBits & 0x02) != 0 { bds.append(20) }
                                    if (bdBits & 0x04) != 0 { bds.append(24) }
                                    bitDepths = bds
                                }
                                
                                let fmtName: String
                                switch fmt {
                                case 1: fmtName = "LPCM"
                                case 2: fmtName = "AC-3"
                                case 7: fmtName = "DTS"
                                case 11: fmtName = "DTS-HD"
                                case 12: fmtName = "Dolby TrueHD"
                                case 15: fmtName = "Extension"
                                default: fmtName = "Format \(fmt)"
                                }
                                audioFormats.append(CTAAudioFormat(formatName: fmtName, maxChannels: maxChannels, sampleRates: sampleRates, bitDepths: bitDepths, maxBitrate: nil))
                            }
                        }
                    } else if tagCode == 2 { // Video
                        blockName = "Video Data Block"
                        videoModes += blockBytes.compactMap(videoMode(fromShortDescriptor:))
                    } else if tagCode == 3 { // Vendor-Specific
                        blockName = "Vendor-Specific Data Block"
                        if blockBytes.count >= 3 {
                            let oui = UInt32(blockBytes[0]) | (UInt32(blockBytes[1]) << 8) | (UInt32(blockBytes[2]) << 16)
                            if oui == 0x000C03 {
                                blockName = "HDMI Vendor-Specific Data Block"
                                hdmiVendorBlock = parseHDMIVSDB(blockBytes, merging: hdmiVendorBlock)
                            } else if oui == 0xC45DD8 {
                                blockName = "HDMI Forum Vendor-Specific Data Block"
                                let forum = parseHDMIForumVSDB(blockBytes)
                                forumMaxTMDSClockMHz = forum.maxTMDSClockMHz
                                forumMaxFRLRateGbps = forum.maxFRLRateGbps
                                if forum.supportsYCbCr420DeepColor { supportsYCbCr420 = true }
                                if let range = forum.vrrRange { vrrRange = range }
                            }
                        }
                    } else if tagCode == 4 { // Speaker Allocation
                        blockName = "Speaker Allocation Data Block"
                        if length >= 3 {
                            let spk = blockBytes[0]
                            speakerAllocation = CTASpeakerAllocation(
                                frontLeftRight: (spk & 0x01) != 0,
                                lfe: (spk & 0x02) != 0,
                                frontCenter: (spk & 0x04) != 0,
                                rearLeftRight: (spk & 0x08) != 0,
                                rearCenter: (spk & 0x10) != 0,
                                frontLeftRightCenter: (spk & 0x20) != 0,
                                rearLeftRightCenter: (spk & 0x40) != 0,
                                topChannels: blockBytes[1] & 0x07 != 0,
                                channelDescription: speakerDescription(spk, extended: blockBytes[1])
                            )
                        }
                    } else if tagCode == 7 { // Extended
                        if length > 0 {
                            extendedTagCode = Int(blockBytes[0])
                            switch extendedTagCode {
                            case 5:
                                blockName = "Colorimetry Data Block"
                                colorimetry = parseColorimetry(blockBytes)
                            case 6:
                                blockName = "HDR Static Metadata Data Block"
                                hdrCapabilities = parseHDRStaticMetadata(blockBytes)
                            case 14:
                                blockName = "YCbCr 4:2:0 Video Data Block"
                                supportsYCbCr420 = true
                                videoModes += blockBytes.dropFirst().compactMap(videoMode(fromShortDescriptor:))
                            case 15:
                                blockName = "YCbCr 4:2:0 Capability Map Data Block"
                                // An empty map means every listed mode also supports 4:2:0.
                                if blockBytes.count == 1 || blockBytes.dropFirst().contains(where: { $0 != 0 }) {
                                    supportsYCbCr420 = true
                                }
                            case 17:
                                blockName = "VRR Data Block"
                            default:
                                blockName = "Extended Data Block (\(extendedTagCode!))"
                            }
                        } else {
                            blockName = "Extended Data Block (Unknown)"
                        }
                    }
                    
                    rawDataBlocks.append(CTARawDataBlock(tagCode: tagCode, extendedTagCode: extendedTagCode, blockName: blockName, length: length, rawBytes: blockBytes))
                    idx += 1 + length
                }
                
                // The HDMI Forum block may precede or follow the HDMI 1.x block, so merge once both are read.
                if forumMaxTMDSClockMHz != nil || forumMaxFRLRateGbps != nil {
                    let current = hdmiVendorBlock
                    var merged = HDMIVendorBlock(
                        maxTMDSClockMHz: [forumMaxTMDSClockMHz, current?.maxTMDSClockMHz].compactMap { $0 }.max(),
                        supports3D: current?.supports3D ?? false,
                        supportsDeepColor30bit: current?.supportsDeepColor30bit ?? false,
                        supportsDeepColor36bit: current?.supportsDeepColor36bit ?? false,
                        supportsDeepColor48bit: current?.supportsDeepColor48bit ?? false,
                        supportsAI: current?.supportsAI ?? false
                    )
                    merged.maxFRLRateGbps = forumMaxFRLRateGbps
                    hdmiVendorBlock = merged
                }

                ctaExtension = CTAExtension(
                    revision: revision,
                    supportsYCbCr444: ctaSupportsYCbCr444,
                    supportsYCbCr422: ctaSupportsYCbCr422,
                    supportsYCbCr420: supportsYCbCr420,
                    supportedVideoModes: videoModes,
                    audioFormats: audioFormats,
                    speakerAllocation: speakerAllocation,
                    hdmiVendorBlock: hdmiVendorBlock,
                    hdrCapabilities: hdrCapabilities,
                    vrrRange: vrrRange,
                    colorimetry: colorimetry,
                    rawDataBlocks: rawDataBlocks
                )
            }
        }
        
        return ParsedEDID(
            manufacturerCode: manufacturerCode,
            manufacturerName: manufacturerName,
            productID: productID,
            serialNumber: serialNumber,
            serialString: serialString,
            manufactureName: manufactureName,
            manufactureWeek: week,
            manufactureYear: year,
            edidVersion: version,
            isDigital: isDigital,
            screenWidthCm: widthCm,
            screenHeightCm: heightCm,
            gamma: gamma,
            supportsRGB444: supportsRGB444,
            supportsYCbCr444: supportsYCbCr444,
            supportsYCbCr422: supportsYCbCr422,
            nativeResolution: nativeResolution,
            detailedTimings: detailedTimings,
            standardTimings: standardTimings,
            establishedTimings: establishedTimings(data[35], data[36], data[37]),
            ctaExtension: ctaExtension,
            rawBytes: data,
            extensionCount: extensionCount
        )
    }
    
    private static func descriptorString(_ bytes: ArraySlice<UInt8>) -> String? {
        let text = bytes.prefix { $0 != 0x0A && $0 != 0x00 }
        guard let string = String(bytes: text, encoding: .ascii) else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func establishedTimings(_ first: UInt8, _ second: UInt8, _ third: UInt8) -> [String] {
        let names: [(UInt8, UInt8, String)] = [
            (first, 0x80, "720x400@70Hz"), (first, 0x40, "720x400@88Hz"),
            (first, 0x20, "640x480@60Hz"), (first, 0x10, "640x480@67Hz"),
            (first, 0x08, "640x480@72Hz"), (first, 0x04, "640x480@75Hz"),
            (first, 0x02, "800x600@56Hz"), (first, 0x01, "800x600@60Hz"),
            (second, 0x80, "800x600@72Hz"), (second, 0x40, "800x600@75Hz"),
            (second, 0x20, "832x624@75Hz"), (second, 0x10, "1024x768i@87Hz"),
            (second, 0x08, "1024x768@60Hz"), (second, 0x04, "1024x768@70Hz"),
            (second, 0x02, "1024x768@75Hz"), (second, 0x01, "1280x1024@75Hz"),
            (third, 0x80, "1152x870@75Hz")
        ]
        return names.filter { $0.0 & $0.1 != 0 }.map(\.2)
    }

    /// CTA-861 VICs a Mac or a TV commonly advertises. Unknown codes are skipped
    /// rather than reported with an invented resolution.
    private static let vicTable: [Int: (width: Int, height: Int, refresh: Double, interlaced: Bool, aspect: String)] = [
        1: (640, 480, 60, false, "4:3"),
        2: (720, 480, 60, false, "4:3"),
        3: (720, 480, 60, false, "16:9"),
        4: (1280, 720, 60, false, "16:9"),
        5: (1920, 1080, 60, true, "16:9"),
        16: (1920, 1080, 60, false, "16:9"),
        17: (720, 576, 50, false, "4:3"),
        18: (720, 576, 50, false, "16:9"),
        19: (1280, 720, 50, false, "16:9"),
        20: (1920, 1080, 50, true, "16:9"),
        31: (1920, 1080, 50, false, "16:9"),
        32: (1920, 1080, 24, false, "16:9"),
        33: (1920, 1080, 25, false, "16:9"),
        34: (1920, 1080, 30, false, "16:9"),
        47: (1280, 720, 120, false, "16:9"),
        63: (1920, 1080, 120, false, "16:9"),
        64: (1920, 1080, 100, false, "16:9"),
        93: (3840, 2160, 24, false, "16:9"),
        94: (3840, 2160, 25, false, "16:9"),
        95: (3840, 2160, 30, false, "16:9"),
        96: (3840, 2160, 50, false, "16:9"),
        97: (3840, 2160, 60, false, "16:9"),
        98: (4096, 2160, 24, false, "256:135"),
        99: (4096, 2160, 25, false, "256:135"),
        100: (4096, 2160, 30, false, "256:135"),
        101: (4096, 2160, 50, false, "256:135"),
        102: (4096, 2160, 60, false, "256:135"),
        117: (3840, 2160, 100, false, "16:9"),
        118: (3840, 2160, 120, false, "16:9"),
        194: (7680, 4320, 24, false, "16:9"),
        195: (7680, 4320, 25, false, "16:9"),
        196: (7680, 4320, 30, false, "16:9"),
        198: (7680, 4320, 50, false, "16:9"),
        199: (7680, 4320, 60, false, "16:9"),
        218: (4096, 2160, 100, false, "256:135"),
        219: (4096, 2160, 120, false, "256:135")
    ]

    /// Short Video Descriptor: values 129–192 carry the native flag on VICs 1–64.
    private static func videoMode(fromShortDescriptor byte: UInt8) -> CTAVideoMode? {
        let raw = Int(byte)
        let isNative = (129...192).contains(raw)
        let vic = isNative ? raw - 128 : raw
        guard let entry = vicTable[vic] else { return nil }
        return CTAVideoMode(
            vic: vic,
            width: entry.width,
            height: entry.height,
            refreshRate: entry.refresh,
            isInterlaced: entry.interlaced,
            isNative: isNative,
            aspectRatio: entry.aspect
        )
    }

    /// HDMI 1.x VSDB: OUI(3) + physical address(2), then optional flag, TMDS and latency bytes.
    private static func parseHDMIVSDB(_ bytes: [UInt8], merging current: HDMIVendorBlock?) -> HDMIVendorBlock {
        let flags: UInt8 = bytes.count > 5 ? bytes[5] : 0
        let maxTMDS = bytes.count > 6 && bytes[6] != 0 ? Int(bytes[6]) * 5 : nil
        var supports3D = false
        if bytes.count > 7 {
            let latencyFlags = bytes[7]
            var position = 8
            if latencyFlags & 0x80 != 0 { position += 2 }
            if latencyFlags & 0x40 != 0 { position += 2 }
            if latencyFlags & 0x20 != 0, position < bytes.count {
                supports3D = bytes[position] & 0x80 != 0
            }
        }
        return HDMIVendorBlock(
            maxTMDSClockMHz: [maxTMDS, current?.maxTMDSClockMHz].compactMap { $0 }.max(),
            supports3D: supports3D,
            supportsDeepColor30bit: flags & 0x10 != 0,
            supportsDeepColor36bit: flags & 0x20 != 0,
            supportsDeepColor48bit: flags & 0x40 != 0,
            supportsAI: flags & 0x80 != 0
        )
    }

    /// HDMI Forum VSDB (HDMI 2.x): max TMDS character rate, 4:2:0 deep colour and VRR range.
    private static func parseHDMIForumVSDB(_ bytes: [UInt8]) -> (maxTMDSClockMHz: Int?, maxFRLRateGbps: Int?, supportsYCbCr420DeepColor: Bool, vrrRange: VRRRange?) {
        let maxTMDS = bytes.count > 4 && bytes[4] != 0 ? Int(bytes[4]) * 5 : nil
        // Max_FRL_Rate: 1 = 3 lanes × 3 Gb/s … 6 = 4 lanes × 12 Gb/s.
        let frlRates = [1: 9, 2: 18, 3: 24, 4: 32, 5: 40, 6: 48]
        let maxFRL = bytes.count > 7 ? frlRates[Int(bytes[7] >> 4)] : nil
        let deepColor420 = bytes.count > 6 && bytes[6] & 0x07 != 0
        var vrr: VRRRange? = nil
        if bytes.count > 10 {
            let minimum = Int(bytes[9] & 0x3F)
            let maximum = (Int(bytes[9] & 0xC0) << 2) | Int(bytes[10])
            if minimum > 0, maximum > minimum {
                vrr = VRRRange(minRefreshHz: minimum, maxRefreshHz: maximum, supportsAdaptiveSync: true)
            }
        }
        return (maxTMDS, maxFRL, deepColor420, vrr)
    }

    private static func parseColorimetry(_ bytes: [UInt8]) -> [String] {
        guard bytes.count > 1 else { return [] }
        let names: [(UInt8, String)] = [
            (0x01, "xvYCC601"), (0x02, "xvYCC709"), (0x04, "sYCC601"), (0x08, "opYCC601"),
            (0x10, "opRGB"), (0x20, "BT2020cYCC"), (0x40, "BT2020YCC"), (0x80, "BT2020RGB")
        ]
        var result = names.filter { bytes[1] & $0.0 != 0 }.map(\.1)
        if bytes.count > 2, bytes[2] & 0x80 != 0 { result.append("DCI-P3") }
        return result
    }

    /// Luminance codes follow CTA-861.3: max = 50·2^(cv/32), min = max·(cv/255)²/100.
    private static func parseHDRStaticMetadata(_ bytes: [UInt8]) -> HDRCapabilities? {
        guard bytes.count > 1 else { return nil }
        let eotf = bytes[1]
        let maxLuminance = bytes.count > 3 && bytes[3] != 0 ? 50 * pow(2, Double(bytes[3]) / 32) : nil
        let maxFrameAverage = bytes.count > 4 && bytes[4] != 0 ? 50 * pow(2, Double(bytes[4]) / 32) : nil
        let minLuminance: Double? = bytes.count > 5 ? maxLuminance.map { $0 * pow(Double(bytes[5]) / 255, 2) / 100 } : nil
        let supportsPQ = eotf & 0x04 != 0
        let supportsHLG = eotf & 0x08 != 0
        return HDRCapabilities(
            supportsSDR: eotf & 0x01 != 0,
            supportsHDR: eotf & 0x02 != 0 || supportsPQ || supportsHLG,
            supportsSMPTE_ST_2084: supportsPQ,
            supportsHLG: supportsHLG,
            maxLuminanceCdm2: maxLuminance,
            minLuminanceCdm2: minLuminance,
            maxFrameAverageLuminance: maxFrameAverage
        )
    }

    private static func speakerDescription(_ first: UInt8, extended: UInt8) -> String {
        let names: [(UInt8, String)] = [
            (0x01, "FL/FR"), (0x02, "LFE"), (0x04, "FC"), (0x08, "RL/RR"),
            (0x10, "RC"), (0x20, "FLC/FRC"), (0x40, "RLC/RRC"), (0x80, "FLW/FRW")
        ]
        var parts = names.filter { first & $0.0 != 0 }.map(\.1)
        if extended & 0x01 != 0 { parts.append("TpFL/TpFR") }
        if extended & 0x02 != 0 { parts.append("TpC") }
        if extended & 0x04 != 0 { parts.append("TpFC") }
        return parts.isEmpty ? "Speaker configuration" : parts.joined(separator: ", ")
    }

    private static func manufacturerNameFromCode(_ code: String) -> String? {
        let pnpIDs = [
            "SAM": "Samsung",
            "DEL": "Dell",
            "ACR": "Acer",
            "BNQ": "BenQ",
            "LEN": "Lenovo",
            "HWP": "HP",
            "AUS": "ASUS",
            "AOC": "AOC",
            "LGD": "LG Display",
            "GSM": "LG (GoldStar)",
            "APL": "Apple",
            "PHL": "Philips",
            "SHP": "Sharp",
            "SNY": "Sony",
            "MEI": "Panasonic",
            "VSC": "ViewSonic",
            "NEC": "NEC",
            "IVM": "Iiyama",
            "EIZ": "EIZO"
        ]
        return pnpIDs[code]
    }
}
