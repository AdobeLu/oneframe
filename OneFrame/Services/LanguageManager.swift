//
//  LanguageManager.swift
//  OneFrame
//
//  App 内语言切换管理器
//

import Foundation
import UIKit

extension Notification.Name {
    static let languageDidChange = Notification.Name("LanguageDidChange")
}

enum AppLanguage: String, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"

    var displayName: String {
        switch self {
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

final class LanguageManager {

    static let shared = LanguageManager()

    private let languageKey = "OneFrame.AppLanguage"

    private(set) var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: languageKey)
            UserDefaults.standard.synchronize()
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: languageKey),
           let lang = AppLanguage(rawValue: saved) {
            currentLanguage = lang
        } else {
            // 跟随系统首选语言
            let preferred = Locale.preferredLanguages.first ?? "en"
            currentLanguage = preferred.hasPrefix("zh") ? .chinese : .english
        }
    }

    func setLanguage(_ language: AppLanguage) {
        guard language != currentLanguage else { return }
        currentLanguage = language
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }

    func localizedString(for key: String) -> String {
        guard let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

/// 便捷全局函数
func OWLocalized(_ key: String) -> String {
    return LanguageManager.shared.localizedString(for: key)
}
