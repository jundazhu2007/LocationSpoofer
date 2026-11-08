import Foundation
import SwiftUI

/// UI language. `system` follows macOS, including the per-app setting in System Settings → Language & Region → Apps.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case zhHant = "zh-Hant"
    case en
    case ja

    var id: String { rawValue }
    static let supported = ["zh-Hant", "en", "ja"]

    /// Menu display name (each language shows its own name, independent of the UI language).
    var nativeName: String {
        switch self {
        case .system: L("跟隨系統")
        case .zhHant: "繁體中文"   // l10n:ignore
        case .en: "English"
        case .ja: "日本語"   // l10n:ignore
        }
    }
}

/// Thread-safe string lookup. The source text (Traditional Chinese) is the key; falls back to it when no translation exists.
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

    /// Turns the user's choice into an actual language code.
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

/// Returns the string for the current language; with arguments it applies String(format:) (%@ string, %lld integer, %.1f decimal).
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Localizer.shared.string(key)
    return args.isEmpty ? format : String(format: format, locale: Locale(identifier: Localizer.shared.code), arguments: args)
}

/// In-app language choice. `revision` increments on change; the root view is rebuilt with it so all text updates immediately.
@MainActor @Observable
final class LanguageSettings {
    /// Disabled in screenshot mode so the user's language preference is not overwritten.
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
