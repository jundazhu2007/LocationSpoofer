import Foundation
import SwiftUI

/// 介面語言。`system` 會跟隨 macOS(含「系統設定 → 語言與地區 → App」的個別設定)。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case zhHant = "zh-Hant"
    case en
    case ja

    var id: String { rawValue }
    static let supported = ["zh-Hant", "en", "ja"]

    /// 選單顯示名稱(各語言以自己的文字呈現,不隨介面語言改變)。
    var nativeName: String {
        switch self {
        case .system: L("跟隨系統")
        case .zhHant: "繁體中文"   // l10n:ignore
        case .en: "English"
        case .ja: "日本語"   // l10n:ignore
        }
    }
}

/// 執行緒安全的字串查詢。原文(繁體中文)即 key,找不到翻譯時回傳原文。
final class Localizer: @unchecked Sendable {
    static let shared = Localizer()
    private let lock = NSLock()
    private var _code = "zh-Hant"
    private var bundles: [String: Bundle] = [:]

    var code: String { lock.withLock { _code } }
    func set(code: String) { lock.withLock { _code = code } }

    func string(_ key: String) -> String {
        let code = self.code
        if code == "zh-Hant" { return key }
        let bundle: Bundle? = lock.withLock {
            if let b = bundles[code] { return b }
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path) else { return nil }
            bundles[code] = b
            return b
        }
        return bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
    }

    /// 把使用者的選擇換成實際語言代碼。
    static func resolve(_ lang: AppLanguage) -> String {
        if lang != .system { return lang.rawValue }
        for preferred in Bundle.main.preferredLocalizations + Locale.preferredLanguages {
            if preferred.hasPrefix("ja") { return "ja" }
            if preferred.hasPrefix("zh") { return "zh-Hant" }
            if preferred.hasPrefix("en") { return "en" }
        }
        return "en"
    }
}

/// 取得目前語言的字串;有參數時以 String(format:) 套用(%@ 字串、%lld 整數、%.1f 小數)。
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Localizer.shared.string(key)
    return args.isEmpty ? format : String(format: format, locale: Locale(identifier: Localizer.shared.code), arguments: args)
}

/// App 內的語言選擇。變更後 `revision` 會遞增,根視圖以它重建,讓所有文字立即更新。
@MainActor @Observable
final class LanguageSettings {
    /// 截圖模式會關閉,避免覆寫使用者的語言偏好。
    var persistsChanges = true
    var selection: AppLanguage {
        didSet {
            if persistsChanges { UserDefaults.standard.set(selection.rawValue, forKey: "appLanguage") }
            apply()
        }
    }
    private(set) var revision = 0
    private(set) var code = "zh-Hant"

    var locale: Locale { Locale(identifier: code) }

    init() {
        selection = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
        apply()
    }

    private func apply() {
        code = Localizer.resolve(selection)
        Localizer.shared.set(code: code)
        revision += 1
    }
}
