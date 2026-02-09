import Foundation

struct SettingsConstants {
    static let defaultHoldDuration: Double = 0.5
    static let defaultPressCount: Int = 2
    static let configSeparator = "="
    static let keyValuePairCount = 2
    
    static let validModifierKeys = ["cmd", "ctrl", "alt", "shift", "fn", "meta"]
    static let validTriggerTypes = ["hold", "press"]
    static let validSuperKeys = ["cmd", "ctrl", "alt", "shift", "meta"]
    
    static let minDuration: Double = 0
    static let minCount: Int = 1
}