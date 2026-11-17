import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system, tr, en
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L("Sistem dili", "System language")
        case .tr: "Türkçe"
        case .en: "English"
        }
    }
    var resolved: String {
        self == .system ? (Locale.preferredLanguages.first?.hasPrefix("tr") == true ? "tr" : "en") : rawValue
    }
    var locale: Locale { Locale(identifier: resolved) }
}

enum L10n {
    static var language: AppLanguage = .system
}

func L(_ turkish: String, _ english: String) -> String {
    L10n.language.resolved == "tr" ? turkish : english
}
