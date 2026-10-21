import Cocoa
import Testing
@testable import Keyly

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var x = state
        x ^= x >> 33
        x = x &* 0xff51afd7ed558ccd
        x ^= x >> 33
        return x
    }
}

private let pieces = [
    "#", "##", "\\", "\\#", "\\[", "\\>", "[", "]", "[]", "[ ]", ">", "|", "||", "+", "-", "=", ":", "\"", "'",
    " ", "  ", "\t", "\r\n", "\n", "\u{FEFF}", "\u{2028}", "\u{85}", "\0", "\u{FFFD}",
    "CMD", "cmd", "COMMAND", "CTRL", "ctrl", "OPT", "alt", "SHIFT", "shift", "fn", "capslock", "caps lock",
    "⌘", "⌃", "⌥", "⇧", "⇪", "K", "k", "a", "1", "F5", "f12", "up", "Home", "click", "space", "enter", "del", "esc",
    "# App:", "# app:", "# Sheet Name:", "# Hide Default:", "# Group:", "none", "true", "Figma", "com.figma.Desktop",
    "super_key", "trigger_type", "press_count", "hold_duration", "screen_width_ratio", "hold", "press",
    "0", "0.5", "-1", "inf", "nan", "1e308", "500ms", "2s", "70%", "999", "9223372036854775808",
    "ß", "ﬀ", "İ", "🔥", "👨‍👩‍👧", "中文", "é", "e\u{301}", "Ω",
]

private func randomText(_ rng: inout SeededGenerator, lines: Int) -> String {
    (0..<lines).map { _ in
        (0..<Int.random(in: 0...6, using: &rng)).map { _ in pieces.randomElement(using: &rng)! }.joined()
    }.joined(separator: "\n")
}

@Suite struct FuzzTests {
    @Test func settingsAlwaysLandInRange() {
        var rng = SeededGenerator(state: 1)
        for _ in 0..<4000 {
            let settings = SettingsParser.parse(randomText(&rng, lines: 8)).settings
            switch settings.trigger.kind {
            case .press(let count): #expect(SettingsParser.pressCountRange.contains(count))
            case .hold(let seconds): #expect(SettingsParser.holdSecondsRange.contains(seconds))
            }
            #expect(SettingsParser.screenWidthRatioRange.contains(settings.screenWidthRatio))
            #expect(!settings.trigger.label.isEmpty)
            if settings.trigger.isCapsLock {
                #expect(settings.trigger.modifiers.isEmpty && settings.trigger.keyCode == nil)
                if case .hold = settings.trigger.kind { Issue.record("Caps Lock must be pressed, not held") }
            }
        }
    }

    @Test func everySheetLineIsAShortcutOrAProblem() {
        var rng = SeededGenerator(state: 2)
        for round in 0..<3000 {
            let text = randomText(&rng, lines: 12)
            let result = SheetParser.parse(text, defaultName: "f", isGlobal: round % 5 == 0)

            var candidates = 0, emptyCategories = 0
            for raw in ConfigText.lines(text) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                if line.hasPrefix("\\"), let next = line.dropFirst().first, "#[>\\".contains(next) { candidates += 1; continue }
                if line.hasPrefix("#") || line.hasPrefix(">") { continue }
                if line.hasPrefix("[") && line.hasSuffix("]") {
                    if line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces).isEmpty { emptyCategories += 1 }
                    continue
                }
                candidates += 1
            }

            let skipped = result.diagnostics.compactMap { diagnostic -> Int? in
                guard diagnostic.message.hasSuffix("more problem(s) not listed") else { return nil }
                return Int(diagnostic.message.split(separator: " ")[0])
            }.reduce(0, +)
            let lineProblems = result.diagnostics.filter { $0.line != nil }.count

            #expect(result.sheet.shortcuts.count + lineProblems + skipped == candidates + emptyCategories, "\(text.debugDescription)")
            for item in result.sheet.shortcuts {
                #expect(!item.shortcut.isEmpty && !item.action.isEmpty)
                #expect(item.action == item.action.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    @Test func lineParserNeverReturnsBlankParts() {
        var rng = SeededGenerator(state: 3)
        for _ in 0..<50_000 {
            let line = randomText(&rng, lines: 1)
            if let parsed = ShortcutLineParser.parse(line) {
                #expect(!parsed.shortcut.isEmpty && !parsed.action.isEmpty)
            }
        }
    }

    @Test func keyCombosAreConsistent() {
        var rng = SeededGenerator(state: 4)
        for _ in 0..<50_000 {
            let raw = (0..<Int.random(in: 1...4, using: &rng)).map { _ in pieces.randomElement(using: &rng)! }.joined(separator: Bool.random(using: &rng) ? "+" : "")
            guard case .success(let combo) = KeyCombo.parse(raw) else { continue }
            #expect(!combo.label.isEmpty)
            if combo.isCapsLock { #expect(combo.modifiers.isEmpty && combo.keyCode == nil) }
            #expect(combo.keyCode != nil || !combo.modifiers.isEmpty || combo.isCapsLock)
        }
    }

    @Test func parsingTimeGrowsLinearly() {
        var rng = SeededGenerator(state: 5)
        let small = randomText(&rng, lines: 5_000)
        let large = String(repeating: small + "\n", count: 4)
        func time(_ text: String) -> Double {
            let start = Date()
            _ = SheetParser.parse(text, defaultName: "f")
            _ = SettingsParser.parse(text)
            return Date().timeIntervalSince(start)
        }
        let a = time(small), b = time(large)
        #expect(b < a * 8, "\(a)s for 5k lines vs \(b)s for 20k")
    }
}
