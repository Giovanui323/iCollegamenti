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
            if byte0 != 0x01 || byte1 != 0x01 {
                let width = (Int(byte0) + 31) * 8
                let aspectRaw = (byte1 >> 6) & 0x03
                let aspect: String
                switch aspectRaw {
                case 0: aspect = "16:10"
                case 1: aspect = "4:3"
                case 2: aspect = "5:4"
                case 3: aspect = "16:9"
                default: aspect = "Unknown"
                }
                let refresh = Int(byte1 & 0x3F) + 60
                standardTimings.append(EDIDStandardTiming(width: width, height: 0, refreshRate: refresh, aspectRatio: aspect))
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
                let refreshRate = Double(pixelClockHz) / Double(hTotal * vTotal)
                
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
                    let nameBytes = data[(i+5)...(i+17)]
                    if let name = String(bytes: nameBytes, encoding: .ascii) {
                        manufactureName = name.replacingOccurrences(of: "\n", with: "").trimmingCharacters(in: .whitespaces)
                    }
                } else if tag == 0xFF {
                    // Serial String
                    let serialBytes = data[(i+5)...(i+17)]
                    if let serial = String(bytes: serialBytes, encoding: .ascii) {
                        serialString = serial.replacingOccurrences(of: "\n", with: "").trimmingCharacters(in: .whitespaces)
                    }
                } else if tag == 0xFD {
                    // Range Limits
                    // Implement if needed
                }
            }
        }
        
        let nativeResolution = detailedTimings.first.map { EDIDResolution(width: $0.hActive, height: $0.vActive) }
        
        let extensionCount = Int(data[126])
        var ctaExtension: CTAExtension? = nil
        
        if extensionCount > 0 && data.count >= 256 {
            let extData = Array(data[128...255])
            if extData[0] == 0x02 { // CTA Tag
                let revision = Int(extData[1])
                let dtdOffset = Int(extData[2])
                let ycbcrFlags = extData[3]
                let ctaSupportsYCbCr444 = (ycbcrFlags & 0x20) != 0
                let ctaSupportsYCbCr422 = (ycbcrFlags & 0x10) != 0
                
                var rawDataBlocks: [CTARawDataBlock] = []
                var audioFormats: [CTAAudioFormat] = []
                var speakerAllocation: CTASpeakerAllocation? = nil
                
                var idx = 4
                let endIdx = (dtdOffset > 4 && dtdOffset <= 127) ? dtdOffset : extData.count
                while idx < endIdx {
                    let header = extData[idx]
                    let tagCode = Int(header >> 5)
                    let length = Int(header & 0x1F)
                    
                    if idx + 1 + length > extData.count { break }
                    let blockBytes = Array(extData[(idx+1)...(idx+length)])
                    
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
                    } else if tagCode == 3 { // Vendor-Specific
                        blockName = "Vendor-Specific Data Block"
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
                                topChannels: false,
                                channelDescription: "Speaker configuration"
                            )
                        }
                    } else if tagCode == 7 { // Extended
                        if length > 0 {
                            extendedTagCode = Int(blockBytes[0])
                            if extendedTagCode == 5 { blockName = "Colorimetry Data Block" }
                            else if extendedTagCode == 6 { blockName = "HDR Static Metadata Data Block" }
                            else if extendedTagCode == 17 { blockName = "VRR Data Block" }
                            else { blockName = "Extended Data Block (\(extendedTagCode!))" }
                        } else {
                            blockName = "Extended Data Block (Unknown)"
                        }
                    }
                    
                    rawDataBlocks.append(CTARawDataBlock(tagCode: tagCode, extendedTagCode: extendedTagCode, blockName: blockName, length: length, rawBytes: blockBytes))
                    idx += 1 + length
                }
                
                ctaExtension = CTAExtension(
                    revision: revision,
                    supportsYCbCr444: ctaSupportsYCbCr444,
                    supportsYCbCr422: ctaSupportsYCbCr422,
                    supportsYCbCr420: false,
                    supportedVideoModes: [],
                    audioFormats: audioFormats,
                    speakerAllocation: speakerAllocation,
                    hdmiVendorBlock: nil,
                    hdrCapabilities: nil,
                    vrrRange: nil,
                    colorimetry: [],
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
            establishedTimings: [],
            ctaExtension: ctaExtension,
            rawBytes: data,
            extensionCount: extensionCount
        )
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
