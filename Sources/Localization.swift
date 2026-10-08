import Foundation
import SwiftUI

/// Supported interface languages.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zh = "zh-Hans"
    case en = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "language_system".localized
        case .zh: return "language_zh".localized
        case .en: return "language_en".localized
        }
    }
}

extension Notification.Name {
    static let ghubLanguageChanged = Notification.Name("dev.ghub.languageChanged")
}

/// Centralized localization manager that allows dynamic switching between languages.
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var currentLanguage: String {
        didSet {
            UserDefaults.standard.set(currentLanguage, forKey: PrefKey.language)
            updateActiveBundle()
            NotificationCenter.default.post(name: .ghubLanguageChanged, object: nil)
        }
    }

    @Published private(set) var activeBundle: Bundle = .main

    private init() {
        let saved = UserDefaults.standard.string(forKey: PrefKey.language) ?? AppLanguage.system.rawValue
        self.currentLanguage = saved
        updateActiveBundle()
    }

    func updateActiveBundle() {
        if currentLanguage == AppLanguage.system.rawValue {
            // Check system preferred language
            let preferred = Locale.preferredLanguages.first ?? "zh-Hans"
            if preferred.starts(with: "en") {
                if let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
                   let bundle = Bundle(path: path) {
                    activeBundle = bundle
                    return
                }
            } else {
                if let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
                   let bundle = Bundle(path: path) {
                    activeBundle = bundle
                    return
                }
            }
            activeBundle = .main
        } else if let path = Bundle.main.path(forResource: currentLanguage, ofType: "lproj"),
                  let bundle = Bundle(path: path) {
            activeBundle = bundle
        } else {
            activeBundle = .main
        }
    }

    func localized(_ key: String) -> String {
        let val = activeBundle.localizedString(forKey: key, value: nil, table: nil)
        if val == key {
            // Fallback to main bundle
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }
        return val
    }
}

extension String {
    /// Localized version of this key using the currently selected language.
    var localized: String {
        LocalizationManager.shared.localized(self)
    }

    func localized(with arguments: CVarArg...) -> String {
        let format = LocalizationManager.shared.localized(self)
        return String(format: format, arguments: arguments)
    }
}
