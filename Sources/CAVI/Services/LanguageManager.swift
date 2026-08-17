import SwiftUI
import Observation

public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case italian = "it"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .english: return "English"
        case .italian: return "Italiano"
        }
    }
    
    public var nativeName: String {
        switch self {
        case .english: return "English (Native)"
        case .italian: return "Italiano"
        }
    }
    
    public var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .italian: return "🇮🇹"
        }
    }
    
    public var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en_US")
        case .italian: return Locale(identifier: "it_IT")
        }
    }
}

@Observable
public final class LanguageManager {
    public var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "app_language")
        }
    }
    
    public var showLanguagePrompt: Bool
    
    public init() {
        let hasChosen = UserDefaults.standard.bool(forKey: "has_chosen_language_v1")
        let savedLangCode = UserDefaults.standard.string(forKey: "app_language") ?? AppLanguage.english.rawValue
        let initialLang = AppLanguage(rawValue: savedLangCode) ?? .english
        
        self.currentLanguage = initialLang
        self.showLanguagePrompt = !hasChosen
    }
    
    public func selectLanguage(_ language: AppLanguage) {
        self.currentLanguage = language
        UserDefaults.standard.set(true, forKey: "has_chosen_language_v1")
        self.showLanguagePrompt = false
    }
    
    public func promptLanguageSelection() {
        self.showLanguagePrompt = true
    }
    
    public func t(_ en: String, _ it: String) -> String {
        switch currentLanguage {
        case .english: return en
        case .italian: return it
        }
    }
}
