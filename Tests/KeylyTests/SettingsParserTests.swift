import Cocoa
import Testing
@testable import Keyly

@Suite struct SettingsParserTests {
    private func parse(_ text: String) -> (settings: KeylySettings, diagnostics: [ConfigDiagnostic]) {
        SettingsParser.parse(text)
    }

    @Test(arguments: ["", "   \n\n", "# only comments\n# here", "\u{FEFF}", "[keyly]\n"])
    func emptyFilesUseDefaults(_ text: String) {
        let result = parse(text)
        #expect(result.settings == .defaults)
        #expect(result.diagnostics.isEmpty)
    }

    @Test func defaultFileIsAllDefaults() {
        let result = parse(ConfigManager.defaultSettingsContent)
        #expect(result.settings == .defaults)
        #expect(result.diagnostics.isEmpty)
    }

    @Test func forgivingNamesAndValues() {
        let result = parse("""
        Super_Key = "Ctrl + K"   # mine
        TRIGGER-TYPE: Hold
        hold duration = 500ms
        """)
        let trigger = result.settings.trigger
        #expect(trigger.keyCode == AppConstants.KeyCodes.k)
        #expect(trigger.modifiers == .control)
        #expect(trigger.kind == .hold(seconds: 0.5))
        #expect(trigger.label == "⌃K")
        #expect(result.diagnostics.isEmpty)
    }

    struct ComboCase: Sendable, CustomStringConvertible {
        let value: String
        let modifiers: NSEvent.ModifierFlags
        let keyCode: UInt16?
        var description: String { value }
    }

    @Test(arguments: [
        ComboCase(value: "cmd", modifiers: .command, keyCode: nil),
        ComboCase(value: "command+option+k", modifiers: [.command, .option], keyCode: AppConstants.KeyCodes.k),
        ComboCase(value: "⌘⇧K", modifiers: [.command, .shift], keyCode: AppConstants.KeyCodes.k),
        ComboCase(value: "⌃⌥ Space", modifiers: [.control, .option], keyCode: AppConstants.KeyCodes.space),
        ComboCase(value: "opt+esc", modifiers: .option, keyCode: AppConstants.KeyCodes.escape),
        ComboCase(value: "ctrl+page up", modifiers: .control, keyCode: AppConstants.KeyCodes.pageUp),
        ComboCase(value: "shift+f12", modifiers: .shift, keyCode: AppConstants.KeyCodes.f12),
        ComboCase(value: "cmd+enter", modifiers: .command, keyCode: AppConstants.KeyCodes.returnKey),
        ComboCase(value: "ctrl+del", modifiers: .control, keyCode: AppConstants.KeyCodes.delete),
        ComboCase(value: "ctrl+keypad enter", modifiers: .control, keyCode: AppConstants.KeyCodes.enter),
    ])
    func superKeyForms(_ combo: ComboCase) {
        let result = parse("super_key = \(combo.value)")
        #expect(result.settings.trigger.modifiers == combo.modifiers)
        #expect(result.settings.trigger.keyCode == combo.keyCode)
        #expect(!result.settings.trigger.isCapsLock)
        #expect(result.diagnostics.isEmpty)
    }

    @Test(arguments: ["hyper", "cmd+a+b", "capslock+cmd", "⌘+💥", "++", "cmd+", "cmd++", "+", "ctrl + + k", "fn+up", "fn+f1", "fn+home", "fn+delete", "fn+return"])
    func badSuperKeyFallsBackToCapsLock(_ value: String) {
        let result = parse("super_key = \(value)\ntrigger_type = hold")
        #expect(result.settings.trigger == .capsLock)
        #expect(!result.diagnostics.isEmpty)
    }

    @Test func customKeyWithoutTriggerTypeHolds() {
        #expect(parse("super_key = cmd").settings.trigger.kind == .hold(seconds: 0.5))
        #expect(parse("super_key = cmd\ntrigger_type = press").settings.trigger.kind == .press(count: 2))
    }

    @Test func capsLockIsAlwaysPressed() {
        let result = parse("super_key = caps lock\ntrigger_type = hold")
        #expect(result.settings.trigger == .capsLock)
        #expect(result.diagnostics.count == 1)
    }

    @Test(arguments: [
        ("0.5", 0.5), ("1s", 1), ("250 ms", 0.25), ("2 seconds", 2),
        ("inf", 3), ("1e308", 3), ("99", 3), ("-1", 0.1), ("0", 0.1), ("0.000001", 0.1),
    ])
    func holdDurationIsClamped(_ value: String, _ expected: Double) {
        let result = parse("super_key = cmd\nhold_duration = \(value)")
        #expect(result.settings.trigger.kind == .hold(seconds: expected))
    }

    @Test(arguments: ["abc", "nan", "0.5 minutes", "--1"])
    func unreadableHoldDurationUsesDefault(_ value: String) {
        let result = parse("super_key = cmd\nhold_duration = \(value)")
        #expect(result.settings.trigger.kind == .hold(seconds: 0.5))
        #expect(result.diagnostics.count == 1)
    }

    @Test(arguments: [("1", 1), ("3", 3), ("999", 4), ("0", 1), ("-5", 1), ("9223372036854775807", 4), ("1.5", 2), ("two", 2)])
    func pressCountIsClamped(_ value: String, _ expected: Int) {
        #expect(parse("press_count = \(value)").settings.trigger.kind == .press(count: expected))
    }

    @Test(arguments: [("0.5", 0.5), ("80%", 0.8), ("5", 1.0), ("0", 0.1), ("wide", 0.7), ("nan", 0.7)])
    func screenWidthRatio(_ value: String, _ expected: Double) {
        #expect(parse("screen_width_ratio = \(value)").settings.screenWidthRatio == expected)
    }

    @Test func typoGetsASuggestion() {
        let result = parse("hold_duratoin = 1")
        #expect(result.diagnostics.first?.message.contains("Did you mean hold_duration?") == true)
        #expect(result.diagnostics.first?.line == 1)
    }

    @Test func lineNumbersSurviveCRLF() {
        let result = parse("# a\r\n\r\nsuper_key = nope\r\n")
        #expect(result.diagnostics.first?.line == 3)
    }

    @Test func utf16FilesAreRead() {
        let text = "super_key = ctrl+k\n"
        for encoding in [String.Encoding.utf16LittleEndian, .utf16BigEndian] {
            var data = Data(encoding == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF])
            data.append(text.data(using: encoding)!)
            let result = parse(ConfigText.decode(data))
            #expect(result.settings.trigger.label == "⌃K")
            #expect(result.diagnostics.isEmpty)
        }
    }

    @Test func onlyRealLineBreaksCountForLineNumbers() {
        let result = parse("# a\u{2028}still the comment\u{85}\u{0B}\u{0C}\nsuper_key = nope")
        #expect(result.diagnostics.first?.line == 2)
    }

    @Test func lastValueWins() {
        #expect(parse("press_count = 3\npress_count = 1").settings.trigger.kind == .press(count: 1))
    }

    @Test func garbageNeverCrashes() {
        let garbage = [
            "=", "==", "=value", "name=", "\0\0\0", String(repeating: "x", count: 100_000),
            "super_key = \(String(repeating: "+", count: 10_000))", "🔥🔥 = 🔥", "super_key=\u{FFFD}\u{FFFD}",
        ]
        for text in garbage {
            _ = parse(text)
        }
        _ = parse(ConfigText.decode(Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) })))
    }
}
