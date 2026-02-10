import Foundation

struct SuperKeySettings {
    let key: String
    let triggerType: String

    var keyComponents: [String] {
        return key.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }

    var modifiers: [String] {
        return keyComponents.filter { SettingsConstants.validModifierKeys.contains($0) }
    }

    var mainKey: String? {
        return keyComponents.first { !SettingsConstants.validModifierKeys.contains($0) }
    }

    var hasModifiers: Bool {
        return !modifiers.isEmpty
    }
}

struct HoldSettings {
    let duration: Double
}

struct PressSettings {
    let count: Int
}

struct UISettings {
    let screenWidthRatio: Double
}

struct KeylySettings {
    let superKey: SuperKeySettings
    let hold: HoldSettings
    let press: PressSettings
    let ui: UISettings
}

final class SettingsManager {
    static let shared = SettingsManager()

    private var currentSettings: KeylySettings?

    private init() {}

    func getSettings() -> KeylySettings {
        if let settings = currentSettings {
            return settings
        }

        let settings = loadSettings()
        currentSettings = settings
        return settings
    }

    func reloadSettings() {
        currentSettings = loadSettings()
    }

    private func loadSettings() -> KeylySettings {
        let defaultSettings = KeylySettings(
            superKey: SuperKeySettings(key: "cmd", triggerType: "hold"),
            hold: HoldSettings(duration: SettingsConstants.defaultHoldDuration),
            press: PressSettings(count: SettingsConstants.defaultPressCount),
            ui: UISettings(screenWidthRatio: 0.7)
        )

        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".config/keyly", isDirectory: true)
        let settingsFile = configDir.appendingPathComponent("setting.conf")

        guard let userConfig = loadUserConfig(from: settingsFile) else {
            return defaultSettings
        }

        let finalSettings = mergeSettings(defaults: defaultSettings, userConfig: userConfig)

        return finalSettings
    }

    private func loadUserConfig(from settingsFile: URL) -> [String: String]? {
        guard FileManager.default.fileExists(atPath: settingsFile.path) else {
            return nil
        }

        guard let content = try? String(contentsOf: settingsFile, encoding: .utf8) else {
            print("[Keyly] Warning: Could not read settings file at \(settingsFile.path)")
            return nil
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[Keyly] Warning: Settings file is empty")
            return nil
        }

        var config: [String: String] = [:]

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }

            let components = trimmedLine.components(separatedBy: SettingsConstants.configSeparator)
            if components.count == SettingsConstants.keyValuePairCount {
                let key = components[0].trimmingCharacters(in: .whitespaces)
                let value = components[1].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty && !value.isEmpty {
                    config[key] = value
                } else {
                    print("[Keyly] Warning: Empty key or value in settings line: '\(trimmedLine)'")
                }
            } else {
                print("[Keyly] Warning: Invalid settings line format: '\(trimmedLine)'")
            }
        }

        return config.isEmpty ? nil : config
    }

    private func mergeSettings(defaults: KeylySettings, userConfig: [String: String]) -> KeylySettings {
        let superKeyKey = validateSuperKey(userConfig["super_key"], default: defaults.superKey.key)
        let triggerType = validateTriggerType(userConfig["trigger_type"], default: defaults.superKey.triggerType)

        let superKey = SuperKeySettings(key: superKeyKey, triggerType: triggerType)

        let holdDuration = validateHoldDuration(userConfig["hold_duration"], default: defaults.hold.duration)
        let hold = HoldSettings(duration: holdDuration)

        let pressCount = validatePressCount(userConfig["press_count"], default: defaults.press.count)
        let press = PressSettings(count: pressCount)

        let screenWidthRatio = validateScreenWidthRatio(userConfig["screen_width_ratio"], default: defaults.ui.screenWidthRatio)
        let ui = UISettings(screenWidthRatio: screenWidthRatio)

        return KeylySettings(
            superKey: superKey,
            hold: hold,
            press: press,
            ui: ui
        )
    }

    private func validateSuperKey(_ value: String?, default defaultValue: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            if value != nil {
                print("[Keyly] Warning: Empty super_key value, using default '\(defaultValue)'")
            }
            return defaultValue
        }

        return value
    }

    private func validateTriggerType(_ value: String?, default defaultValue: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return defaultValue
        }

        let validTypes = ["hold", "press"]
        if validTypes.contains(value) {
            return value
        } else {
            print("[Keyly] Warning: Invalid trigger_type '\(value)', using default '\(defaultValue)'")
            return defaultValue
        }
    }

    private func validateHoldDuration(_ value: String?, default defaultValue: Double) -> Double {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let duration = Double(value),
              duration > SettingsConstants.minDuration else {
            if let value = value {
                print("[Keyly] Warning: Invalid hold_duration '\(value)', using default \(defaultValue)")
            }
            return defaultValue
        }
        return duration
    }

    private func validatePressCount(_ value: String?, default defaultValue: Int) -> Int {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let count = Int(value),
              count >= SettingsConstants.minCount else {
            if let value = value {
                print("[Keyly] Warning: Invalid press_count '\(value)', using default \(defaultValue)")
            }
            return defaultValue
        }
        return count
    }

    private func validateScreenWidthRatio(_ value: String?, default defaultValue: Double) -> Double {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let ratio = Double(value) else {
            if let value = value {
                print("[Keyly] Warning: Invalid screen_width_ratio '\(value)', using default \(defaultValue)")
            }
            return defaultValue
        }

        // Clamp between 0.1 and 1.0 to prevent overUI on 14inch and negative values
        let clampedRatio = max(0.1, min(1.0, ratio))
        
        if clampedRatio != ratio {
            print("[Keyly] Warning: screen_width_ratio '\(ratio)' clamped to \(clampedRatio) (valid range: 0.1-1.0)")
        }
        
        return clampedRatio
    }
}
