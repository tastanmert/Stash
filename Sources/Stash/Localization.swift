import Foundation

/// Localized string for an English source key (falls back to the key itself).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Localized format string for an English source key.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: .current, arguments: args)
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", turkish = "tr"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: L("System Language")
        case .english: "English"
        case .turkish: "Türkçe"
        }
    }

    static var current: AppLanguage {
        guard let list = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = list.first else { return .system }
        return first.hasPrefix("tr") ? .turkish : .english
    }

    func apply() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}
