import SwiftUI

struct LanguageSelectionSheet: View {
    @Environment(LanguageManager.self) private var languageManager
    @State private var selectedLanguage: AppLanguage = .english
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon & Welcome
            VStack(spacing: 10) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                
                Text(selectedLanguage == .english ? "Welcome to iCollegamenti" : "Benvenuto in iCollegamenti")
                    .font(.title.weight(.bold))
                
                Text(selectedLanguage == .english 
                     ? "Please choose your preferred language to get started.\nYou can change this anytime from the menu bar."
                     : "Scegli la tua lingua preferita per iniziare.\nPuoi cambiarla in qualsiasi momento dalla barra dei menu.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Language Selection Cards
            HStack(spacing: 16) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        selectedLanguage = language
                    } label: {
                        VStack(spacing: 12) {
                            Text(language.flag)
                                .font(.system(size: 36))
                            
                            VStack(spacing: 3) {
                                Text(language.displayName)
                                    .font(.headline.weight(.semibold))
                                    .foregroundColor(.primary)
                                
                                if language == .english {
                                    Text("Native")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(.blue.opacity(0.15)))
                                        .foregroundStyle(.blue)
                                } else {
                                    Text("Italiano")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(width: 150, height: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedLanguage == language ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(selectedLanguage == language ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selectedLanguage == language ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            
            // Confirm Button
            Button {
                languageManager.selectLanguage(selectedLanguage)
            } label: {
                Text(selectedLanguage == .english ? "Continue" : "Continua")
                    .font(.headline.weight(.semibold))
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(width: 440, height: 380)
        .onAppear {
            selectedLanguage = languageManager.currentLanguage
        }
    }
}
