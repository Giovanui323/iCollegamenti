import Foundation
import AppKit

@MainActor
public enum AppIconHelper {
    public static var logoImage: NSImage? {
        // 1. Try Bundle.module URL without subdirectory
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // 2. Try Bundle.module with subdirectory
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Resources"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // 3. Try Bundle.main URL
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // 4. Try Bundle.main ICNS
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        // 5. Try NSImage named
        if let image = NSImage(named: "AppIcon") {
            return image
        }
        // 6. Direct relative file path fallback for local debugging
        let localPath = "Sources/CAVI/Resources/AppIcon.png"
        if FileManager.default.fileExists(atPath: localPath),
           let image = NSImage(contentsOfFile: localPath) {
            return image
        }
        
        return nil
    }
}
