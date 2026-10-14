import Foundation

final class UserDefaultsSettingsRepository: SettingsRepository {
    private enum Key {
        static let onboardingCompleted = "settings.onboardingCompleted"
        static let defaultCurrency = "settings.defaultCurrency"
        static let hapticsEnabled = "settings.hapticsEnabled"
        static let lastExportAt = "settings.lastExportAt"
        static let all = [onboardingCompleted, defaultCurrency, hapticsEnabled, lastExportAt]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        let fallback = AppSettings.default
        return AppSettings(
            onboardingCompleted: defaults.object(forKey: Key.onboardingCompleted) as? Bool ?? fallback.onboardingCompleted,
            defaultCurrency: (defaults.string(forKey: Key.defaultCurrency)).flatMap(CurrencyCode.init(rawValue:)) ?? fallback.defaultCurrency,
            hapticsEnabled: defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? fallback.hapticsEnabled,
            lastExportAt: defaults.object(forKey: Key.lastExportAt) as? Date
        )
    }

    func save(_ settings: AppSettings) {
        defaults.set(settings.onboardingCompleted, forKey: Key.onboardingCompleted)
        defaults.set(settings.defaultCurrency.rawValue, forKey: Key.defaultCurrency)
        defaults.set(settings.hapticsEnabled, forKey: Key.hapticsEnabled)
        if let date = settings.lastExportAt {
            defaults.set(date, forKey: Key.lastExportAt)
        } else {
            defaults.removeObject(forKey: Key.lastExportAt)
        }
    }

    func reset() {
        Key.all.forEach(defaults.removeObject(forKey:))
    }
}
