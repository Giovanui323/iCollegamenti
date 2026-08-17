import Foundation
import Observation

/// Resolves USB Vendor IDs and Product IDs using official USB-IF and linux-usb.org repositories.
/// Downloaded catalog data is cached locally in UserDefaults so lookups continue working offline.
@Observable
@MainActor
final class USBVendorCatalog {
    private static let usbifURL = URL(string: "https://cms.usb.org/usb/api/usbif.json")!
    private static let linuxUsbIdsURL = URL(string: "https://www.linux-usb.org/usb.ids")!
    private static let cacheKeyVendors = "usbif.vendorCatalog.v2.vendors"
    private static let cacheKeyProducts = "usbif.vendorCatalog.v2.products"
    
    private var vendors: [Int: String] = [
        // Storage & Flash Memory
        0x0781: "SanDisk",
        0x0951: "Kingston",
        0x1058: "Western Digital",
        0x0BC2: "Seagate",
        0x04E8: "Samsung",
        0x054C: "Sony",
        0x0930: "Toshiba / Kioxia",
        0x0634: "Micron / Crucial",
        0x8564: "Transcend",
        0x05DC: "Lexar",
        0x154B: "PNY",
        0x1B1C: "Corsair",
        0x2077: "Sabrent",
        0x125F: "ADATA",
        0x059F: "LaCie",
        0x1E68: "OWC (Other World Computing)",
        0x322E: "CalDigit",
        0x18A5: "Verbatim",
        0x1005: "Apacer",
        0x13FE: "Phison / Silicon Power",
        0x0DD8: "Netac",
        0x1E3D: "Chipsbank / Goodram",
        0x1307: "Transcend Information",
        0x1687: "Kingmax",

        // Controller & Bridge ICs
        0x152D: "JMicron",
        0x174C: "ASMedia",
        0x0BDA: "Realtek",
        0x2109: "VIA Labs",
        0x05E3: "Genesys Logic",
        0x090C: "Silicon Motion",
        0x058F: "Alcor Micro",
        0x1F75: "Innostor",
        0x067B: "Prolific",
        0x0403: "FTDI",
        0x04B4: "Cypress / Infineon",
        0x10C4: "Silicon Labs",
        0x0483: "STMicroelectronics",
        0x1A86: "Winchiphead (CH340)",
        0x0424: "Microchip / SMSC",
        0x04D8: "Microchip",
        0x0451: "Texas Instruments",
        0x17E9: "DisplayLink",
        0x1A40: "Terminus Technology",
        0x214B: "Huaxin",

        // Computer & Tech Brands
        0x05AC: "Apple",
        0x046D: "Logitech",
        0x045E: "Microsoft",
        0x0B05: "ASUS",
        0x413C: "Dell",
        0x03F0: "HP",
        0x17EF: "Lenovo",
        0x043E: "LG Electronics",
        0x8086: "Intel",
        0x8087: "Intel Wireless",
        0x1022: "AMD",
        0x0A5C: "Broadcom",
        0x0CF3: "Qualcomm Atheros",
        0x0E8D: "MediaTek",
        0x18D1: "Google",
        0x2B7E: "UGREEN",
        0x29EA: "Anker",
        0x050D: "Belkin",
        0x2E66: "Satechi",
        0x14B0: "StarTech",
        0x0FD9: "Elgato",
        0x1532: "Razer",
        0x1038: "SteelSeries",
        0x3434: "Keychron",
        0x056A: "Wacom",
        0x2E8A: "Raspberry Pi",
        0x2341: "Arduino",
        0x239A: "Adafruit",
        0x1050: "Yubico",
        0x1235: "Focusrite",
        0x1397: "Behringer",
        0x0763: "M-Audio",
        0x04A9: "Canon",
        0x04B8: "Epson",
        0x04F9: "Brother",
        0x057E: "Nintendo",
        0x28DE: "Valve (Steam)",
        0x12D1: "Huawei",
        0x2717: "Xiaomi",
        0x2357: "TP-Link",
        0x2001: "D-Link",
        0x0846: "Netgear",
        0x13B1: "Linksys"
    ]
    
    private var products: [String: String] = [
        "0781:5583": "SanDisk Ultra Fit",
        "0781:5588": "SanDisk Extreme Pro",
        "0781:5590": "SanDisk Ultra Dual Drive USB-C",
        "0781:5591": "SanDisk Ultra Flair",
        "0781:5597": "SanDisk Ultra Luxe",
        "0781:55ae": "SanDisk Extreme Portable SSD",
        "0781:55af": "SanDisk Extreme Pro Portable SSD",
        "0781:5567": "SanDisk Cruzer Blade",
        "0781:5572": "SanDisk Cruzer Edge",
        "04e8:61f5": "Samsung Portable SSD T7",
        "04e8:61f1": "Samsung Portable SSD T5",
        "04e8:4001": "Samsung Portable SSD T9",
        "04e8:61b6": "Samsung Portable SSD X5",
        "1058:25e1": "WD My Passport",
        "1058:2627": "WD Elements SE",
        "1058:0820": "WD My Passport Ultra",
        "0951:1666": "Kingston DataTraveler 100 G3",
        "0951:1665": "Kingston DataTraveler SE9",
        "0951:16a4": "Kingston DataTraveler Exodia",
        "0951:166c": "Kingston DataTraveler Kyson",
        "152d:0578": "JMicron JMS578 SATA Bridge",
        "152d:0583": "JMicron JMS583 NVMe Bridge",
        "174c:55aa": "ASMedia ASM1051/1053 SATA Bridge",
        "174c:2362": "ASMedia ASM2362 NVMe PCIe Bridge",
        "174c:2464": "ASMedia ASM2464PD USB4/TB4 Bridge",
        "0bda:9210": "Realtek RTL9210 NVMe/SATA Bridge",
        "2109:0715": "VIA Labs VL715/VL716 SATA Bridge"
    ]

    init() {
        loadCache()
    }

    func name(for vendorID: Int?) -> String? {
        guard let vendorID else { return nil }
        return vendors[vendorID]
    }

    func productName(for vendorID: Int?, productID: Int?) -> String? {
        guard let vendorID, let productID else { return nil }
        let key = String(format: "%04x:%04x", vendorID, productID)
        return products[key]
    }

    func update() async {
        await fetchLinuxUsbIds()
        await fetchUSBIF()
    }
    
    private func fetchLinuxUsbIds() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.linuxUsbIdsURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { return }
            
            let (parsedVendors, parsedProducts) = Self.parseLinuxUsbIds(text)
            if !parsedVendors.isEmpty {
                vendors.merge(parsedVendors) { _, new in new }
                products.merge(parsedProducts) { _, new in new }
                saveCache()
            }
        } catch {
            // Keep cached & default catalog offline
        }
    }

    private func fetchUSBIF() async {
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.usbifURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let parsed = try Self.parseUSBIF(data)
            guard !parsed.isEmpty else { return }
            vendors.merge(parsed) { _, official in official }
            saveCache()
        } catch {
            // Keep cached catalog offline
        }
    }

    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKeyVendors),
           let cached = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in cached {
                if let vid = Int(key) { vendors[vid] = value }
            }
        }
        if let data = UserDefaults.standard.data(forKey: Self.cacheKeyProducts),
           let cached = try? JSONDecoder().decode([String: String].self, from: data) {
            products = cached
        }
    }

    private func saveCache() {
        let serializableVendors = Dictionary(uniqueKeysWithValues: vendors.map { (String($0.key), $0.value) })
        if let dataV = try? JSONEncoder().encode(serializableVendors) {
            UserDefaults.standard.set(dataV, forKey: Self.cacheKeyVendors)
        }
        if let dataP = try? JSONEncoder().encode(products) {
            UserDefaults.standard.set(dataP, forKey: Self.cacheKeyProducts)
        }
    }

    private static func parseLinuxUsbIds(_ content: String) -> (vendors: [Int: String], products: [String: String]) {
        var parsedVendors: [Int: String] = [:]
        var parsedProducts: [String: String] = [:]
        var currentVendorID: Int? = nil
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            
            if line.hasPrefix("\t\t") {
                continue
            } else if line.hasPrefix("\t") {
                guard let vendorID = currentVendorID else { continue }
                let trimmed = line.dropFirst().trimmingCharacters(in: .whitespaces)
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2, let pid = Int(parts[0], radix: 16) {
                    let productName = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    let key = String(format: "%04x:%04x", vendorID, pid)
                    parsedProducts[key] = productName
                }
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if parts.count == 2, let vid = Int(parts[0], radix: 16) {
                    let vendorName = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    currentVendorID = vid
                    parsedVendors[vid] = vendorName
                }
            }
        }
        
        return (parsedVendors, parsedProducts)
    }

    private static func parseUSBIF(_ data: Data) throws -> [Int: String] {
        let root = try JSONSerialization.jsonObject(with: data)
        var resolved: [Int: String] = [:]
        collect(root, into: &resolved)
        return resolved
    }

    private static func collect(_ value: Any, into result: inout [Int: String]) {
        if let dictionary = value as? [String: Any] {
            let identifier = ["vendor_id", "vendorId", "vid", "id"].compactMap { key -> Int? in
                if let number = dictionary[key] as? NSNumber { return number.intValue }
                if let text = dictionary[key] as? String { return Int(text) }
                return nil
            }.first
            let company = ["company", "company_name", "name"].compactMap { dictionary[$0] as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if let identifier, let company, (0...0xFFFF).contains(identifier) { result[identifier] = company }
            dictionary.values.forEach { collect($0, into: &result) }
        } else if let array = value as? [Any] {
            array.forEach { collect($0, into: &result) }
        }
    }
}
