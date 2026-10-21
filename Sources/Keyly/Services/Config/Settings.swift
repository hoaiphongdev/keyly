import Cocoa

/// The key that opens Keyly, resolved once when settings load so key events only compare integers.
struct Trigger: Equatable {
    enum Kind: Equatable {
        case press(count: Int)
        case hold(seconds: Double)
    }

    /// Human-readable form, e.g. "⌃K" or "⇪"
    let label: String
    /// The non-modifier key, nil for Caps Lock and modifier-only triggers
    let keyCode: UInt16?
    let modifiers: NSEvent.ModifierFlags
    let isCapsLock: Bool
    let kind: Kind

    /// fn is set automatically by arrow and F keys, so it only counts when the trigger asks for it
    private var comparedModifiers: NSEvent.ModifierFlags {
        modifiers.contains(.function) ? [.command, .control, .option, .shift, .function] : [.command, .control, .option, .shift]
    }

    var isModifierOnly: Bool { keyCode == nil && !isCapsLock }

    /// Exactly the trigger's modifiers are down, no more and no fewer
    func matchesModifiers(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection(comparedModifiers) == modifiers
    }

    func matchesKey(_ keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == self.keyCode && matchesModifiers(flags)
    }

    static let capsLock = Trigger(label: "⇪", keyCode: nil, modifiers: [], isCapsLock: true, kind: .press(count: SettingsParser.defaultPressCount))
}

struct KeylySettings: Equatable {
    let trigger: Trigger
    let screenWidthRatio: Double

    static let defaults = KeylySettings(trigger: .capsLock, screenWidthRatio: SettingsParser.defaultScreenWidthRatio)
}

/// Reads `setting.conf`. Forgiving on input, so a typo never stops Keyly from opening:
/// names and values ignore case, quotes and trailing `# comments`, numbers are clamped to a
/// usable range, and anything unreadable falls back to its default with a diagnostic.
enum SettingsParser {
    static let fileName = "setting.conf"

    static let defaultPressCount = 2
    static let defaultHoldSeconds = 0.5
    static let defaultScreenWidthRatio = 0.7
    static let pressCountRange = 1...4
    static let holdSecondsRange = 0.1...3.0
    static let screenWidthRatioRange = 0.1...1.0

    static let knownNames = ["super_key", "trigger_type", "press_count", "hold_duration", "screen_width_ratio"]

    static func parse(_ text: String) -> (settings: KeylySettings, diagnostics: [ConfigDiagnostic]) {
        var diagnostics: [ConfigDiagnostic] = []
        var values: [String: (value: String, line: Int)] = [:]

        for (index, rawLine) in ConfigText.lines(text).enumerated() {
            let lineNumber = index + 1
            let line = stripComment(rawLine).trimmingCharacters(in: .whitespaces)
            // Blank lines and ini-style [section] headers carry nothing
            if line.isEmpty || (line.hasPrefix("[") && line.hasSuffix("]")) { continue }

            guard let separator = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
                diagnostics.append(ConfigDiagnostic(line: lineNumber, message: "Expected name = value"))
                continue
            }

            let name = normalizeName(line[..<separator])
            let value = unquote(line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces))

            guard knownNames.contains(name) else {
                let suggestion = knownNames.min { name.distance(to: $0) < name.distance(to: $1) }
                    .flatMap { name.distance(to: $0) <= 2 ? " Did you mean \($0)?" : nil } ?? ""
                diagnostics.append(ConfigDiagnostic(line: lineNumber, message: "Unknown setting \"\(name)\".\(suggestion)"))
                continue
            }
            guard !value.isEmpty else {
                diagnostics.append(ConfigDiagnostic(line: lineNumber, message: "\(name) has no value, using the default"))
                continue
            }
            values[name] = (value, lineNumber)
        }

        func report(_ name: String, _ message: String) {
            diagnostics.append(ConfigDiagnostic(line: values[name]?.line, message: message))
        }

        // super_key
        var key = KeyCombo.capsLock
        if let (value, _) = values["super_key"] {
            switch KeyCombo.parse(value) {
            case .success(let combo): key = combo
            case .failure(let error): report("super_key", "\(error.message), using Caps Lock")
            }
        }

        // trigger_type: a custom key without one keeps the old default, hold
        var wantsHold = !key.isCapsLock
        if let (value, _) = values["trigger_type"] {
            switch value.lowercased() {
            case "hold": wantsHold = true
            case "press", "tap": wantsHold = false
            default: report("trigger_type", "trigger_type must be press or hold, using \(wantsHold ? "hold" : "press")")
            }
        }
        if key.isCapsLock && wantsHold {
            if values["trigger_type"] != nil { report("trigger_type", "Caps Lock can only be pressed, using press") }
            wantsHold = false
        }

        let kind: Trigger.Kind
        if wantsHold {
            var seconds = defaultHoldSeconds
            if let (value, _) = values["hold_duration"] {
                if let parsed = parseSeconds(value) {
                    seconds = clamp(parsed, to: holdSecondsRange) { report("hold_duration", "hold_duration \(value) is outside \(format(holdSecondsRange.lowerBound))s–\(format(holdSecondsRange.upperBound))s, using \(format($0))s") }
                } else {
                    report("hold_duration", "hold_duration \"\(value)\" isn't a duration like 0.5 or 500ms, using \(format(seconds))s")
                }
            }
            kind = .hold(seconds: seconds)
        } else {
            var count = defaultPressCount
            if let (value, _) = values["press_count"] {
                if let parsed = Int(value) {
                    count = clamp(parsed, to: pressCountRange) { report("press_count", "press_count \(value) is outside \(pressCountRange.lowerBound)–\(pressCountRange.upperBound), using \($0)") }
                } else {
                    report("press_count", "press_count \"\(value)\" isn't a whole number, using \(count)")
                }
            }
            kind = .press(count: count)
        }

        // screen_width_ratio: 0.7 or 70%
        var ratio = defaultScreenWidthRatio
        if let (value, _) = values["screen_width_ratio"] {
            let isPercent = value.hasSuffix("%")
            if let number = Double(isPercent ? String(value.dropLast()).trimmingCharacters(in: .whitespaces) : value), number.isFinite {
                ratio = clamp(isPercent ? number / 100 : number, to: screenWidthRatioRange) { report("screen_width_ratio", "screen_width_ratio \(value) is outside 0.1–1.0, using \(format($0))") }
            } else {
                report("screen_width_ratio", "screen_width_ratio \"\(value)\" isn't a number like 0.7, using \(format(ratio))")
            }
        }

        let trigger = Trigger(label: key.label, keyCode: key.keyCode, modifiers: key.modifiers, isCapsLock: key.isCapsLock, kind: kind)
        return (KeylySettings(trigger: trigger, screenWidthRatio: ratio), diagnostics)
    }

    // MARK: - Helpers

    /// `press_count = 2  # two taps` → `press_count = 2`. Only a `#` after whitespace starts a comment.
    private static func stripComment(_ line: Substring) -> Substring {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { return "" }
        var previous: Character = " "
        for index in line.indices {
            if line[index] == "#" && previous.isWhitespace { return line[..<index] }
            previous = line[index]
        }
        return line
    }

    /// `Hold Duration`, `hold-duration` and `HOLD_DURATION` all mean hold_duration
    private static func normalizeName(_ raw: Substring) -> String {
        raw.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else { return value }
        return String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    /// `0.5`, `0.5s`, `500ms`, `1 sec`
    static func parseSeconds(_ value: String) -> Double? {
        let lower = value.lowercased()
        let units: [(suffix: String, scale: Double)] = [("ms", 0.001), ("seconds", 1), ("second", 1), ("secs", 1), ("sec", 1), ("s", 1)]
        for unit in units where lower.hasSuffix(unit.suffix) {
            let number = lower.dropLast(unit.suffix.count).trimmingCharacters(in: .whitespaces)
            return Double(number).map { $0 * unit.scale }.flatMap { $0.isNaN ? nil : $0 }
        }
        return Double(lower).flatMap { $0.isNaN ? nil : $0 }
    }

    private static func clamp<T: Comparable>(_ value: T, to range: ClosedRange<T>, onChange: (T) -> Void) -> T {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        if clamped != value { onChange(clamped) }
        return clamped
    }

    private static func format(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

/// A key combination written in `super_key`: `capslock`, `cmd`, `ctrl+k`, `Command + Shift + K`, `⌃⌥K`.
struct KeyCombo: Equatable {
    let label: String
    let keyCode: UInt16?
    let modifiers: NSEvent.ModifierFlags
    let isCapsLock: Bool

    static let capsLock = KeyCombo(label: "⇪", keyCode: nil, modifiers: [], isCapsLock: true)

    struct ParseError: Error, Equatable {
        let message: String
    }

    private static let modifierAliases: [String: NSEvent.ModifierFlags] = [
        "cmd": .command, "command": .command, "meta": .command, "⌘": .command,
        "ctrl": .control, "control": .control, "⌃": .control,
        "alt": .option, "opt": .option, "option": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "fn": .function, "globe": .function,
    ]

    private static let capsLockAliases: Set<String> = ["capslock", "caps_lock", "caps", "⇪"]

    private static let keyAliases: [String: String] = [
        "esc": "escape", "⎋": "escape",
        "⏎": "return", "↩": "return",
        "⇥": "tab",
        "backspace": "delete", "⌫": "delete",
        "del": "forward_delete", "⌦": "forward_delete",
        "pageup": "page_up", "pgup": "page_up", "pagedown": "page_down", "pgdn": "page_down",
        "spacebar": "space", "↑": "up", "↓": "down", "←": "left", "→": "right",
    ]

    /// Main-key name → key code, without the modifier names that share the table
    private static let keyCodes: [String: UInt16] = {
        var codes: [String: UInt16] = ["-": 27, "=": 24]
        for (code, name) in AppConstants.KeyCodes.names where modifierAliases[name] == nil {
            codes[name] = code
        }
        return codes
    }()

    private static let modifierGlyphs: [(NSEvent.ModifierFlags, String)] = [
        (.function, "fn"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
    ]

    static func parse(_ raw: String) -> Result<KeyCombo, ParseError> {
        // Glyphs need no "+": ⌃⌥K → ⌃ + ⌥ + K
        var spaced = raw
        for glyph in ["⌘", "⌃", "⌥", "⇧", "⇪"] {
            spaced = spaced.replacingOccurrences(of: glyph, with: "+\(glyph)+")
        }
        let tokens = spaced.split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "_") }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return .failure(ParseError(message: "super_key is empty")) }

        var modifiers: NSEvent.ModifierFlags = []
        var mainKey: (name: String, code: UInt16)?
        var hasCapsLock = false

        for token in tokens {
            if let flag = modifierAliases[token] {
                modifiers.insert(flag)
            } else if capsLockAliases.contains(token) {
                hasCapsLock = true
            } else if let code = keyCodes[keyAliases[token] ?? token] {
                if let existing = mainKey, existing.code != code {
                    return .failure(ParseError(message: "super_key can have only one non-modifier key, found \(existing.name) and \(token)"))
                }
                mainKey = (token, code)
            } else {
                return .failure(ParseError(message: "Unknown key \"\(token)\" in super_key"))
            }
        }

        if hasCapsLock {
            guard modifiers.isEmpty && mainKey == nil else {
                return .failure(ParseError(message: "Caps Lock can't be combined with other keys"))
            }
            return .success(.capsLock)
        }

        let glyphs = modifierGlyphs.filter { modifiers.contains($0.0) }.map(\.1).joined()
        let label = glyphs + (mainKey.map { $0.name.count == 1 ? $0.name.uppercased() : $0.name } ?? "")
        return .success(KeyCombo(label: label, keyCode: mainKey?.code, modifiers: modifiers, isCapsLock: false))
    }
}
