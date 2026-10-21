import Foundation
import Testing
@testable import Keyly

@Suite struct SheetParserTests {
    private func parse(_ text: String, isGlobal: Bool = false) -> (sheet: ShortcutSheet, diagnostics: [ConfigDiagnostic]) {
        SheetParser.parse(text, defaultName: "test", isGlobal: isGlobal)
    }

    @Test func fullSheet() {
        let result = parse("""
        # Sheet Name: Figma
        # app: Figma
        # HIDE DEFAULT: yes
        # a plain comment: with a colon
        ## App: com.disabled.App
        ## Hide Default: false

        # Group: Canvas - Moving around
        [View]
        > Zoom and pan
        ⇧1          Zoom to fit
        CMD+SHIFT+H | Flip horizontal
        # Group: none
        [Edit]
        CMD+D       Duplicate
        """)
        #expect(result.diagnostics.isEmpty)
        #expect(result.sheet.name == "Figma")
        #expect(result.sheet.app == "Figma")
        #expect(result.sheet.hideDefaultShortcuts)
        #expect(result.sheet.categoryDescriptions == ["View": "Zoom and pan"])
        #expect(result.sheet.groupDescriptions == ["Canvas": "Moving around"])
        #expect(result.sheet.shortcuts.map(\.shortcut) == ["⇧1", "⇧⌘H", "⌘D"])
        #expect(result.sheet.shortcuts.map(\.group) == ["Canvas", "Canvas", nil])
        #expect(result.sheet.shortcuts.map(\.category) == ["View", "View", "Edit"])
    }

    @Test func escapedKeysThatLookLikeSyntax() {
        let result = parse("""
        # App: Notion
        \\#           Heading 1
        \\## + space  Heading 2
        \\[x]         Checklist
        \\>           Quote block
        \\            Line segment
        \\\\           Literal backslash
        """)
        #expect(result.diagnostics.isEmpty)
        #expect(result.sheet.shortcuts.map(\.shortcut) == ["#", "## + Space", "[x]", ">", "\\", "\\"])
        #expect(result.sheet.categoryDescriptions.isEmpty)
    }

    @Test func missingAppIsListedFirstEvenPastTheCap() {
        let result = parse(String(repeating: "nope\n", count: 50))
        #expect(result.diagnostics.first?.message.contains("No # App: line") == true)
    }

    @Test func missingAppIsReported() {
        let result = parse("CMD+K  Do it")
        #expect(result.sheet.app == nil)
        #expect(result.diagnostics.count == 1)
    }

    @Test func globalSheetIgnoresAppAndHide() {
        let result = parse("# App: Safari\n# Hide Default: true\n> Everywhere\nCMD+Q  Quit", isGlobal: true)
        #expect(result.diagnostics.isEmpty)
        #expect(result.sheet.app == nil)
        #expect(!result.sheet.hideDefaultShortcuts)
        #expect(result.sheet.shortcuts.first?.category == "Global")
        #expect(result.sheet.categoryDescriptions == ["Global": "Everywhere"])
    }

    @Test func badLinesAreSkippedNotFatal() {
        let result = parse("# App: X\nlonely\nCMD+K  Good\n[]\n|")
        #expect(result.sheet.shortcuts.count == 1)
        #expect(result.diagnostics.map(\.line) == [2, 4, 5])
    }

    @Test func diagnosticsAreCapped() {
        let text = "# App: X\n" + String(repeating: "nope\n", count: 500)
        let result = parse(text)
        #expect(result.diagnostics.count == SheetParser.maxDiagnosticsPerFile + 1)
    }

    @Test func largeFileIsLinear() {
        let text = "# App: X\n[Big]\n" + String(repeating: "CMD+SHIFT+K        Something long enough to matter\n", count: 20_000)
        let start = Date()
        let result = parse(text)
        #expect(result.sheet.shortcuts.count == 20_000)
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func garbageNeverCrashes() {
        let samples = [
            "\u{FEFF}# App: X\r\nCMD+K\tGo\r\n", "[", "]", ">", "#", "\\", "\\\\", "# Group:", "# Group: - - -",
            "# App:", "CMD+", "CMD+ ", "+ +", "ß+ﬀ  x", "COMMAND-", "🧨  boom", String(repeating: "CMD+", count: 5000) + "K  x",
        ]
        for sample in samples {
            _ = parse(sample)
            _ = parse(sample, isGlobal: true)
        }
        _ = parse(ConfigText.decode(Data((0..<8192).map { UInt8(truncatingIfNeeded: $0 &* 131) })))
    }
}

@Suite struct ShortcutLineParserTests {
    @Test(arguments: [
        ("CMD+SHIFT+T    Reopen", "⇧⌘T", "Reopen"),
        ("⇧⌘T | Reopen last tab", "⇧⌘T", "Reopen last tab"),
        ("ctrl-alt-delete\tForce quit", "⌃⌥⌫", "Force quit"),
        ("tool attach <name> | Attach", "tool attach <name>", "Attach"),
        ("⌘+click         Add cursor", "⌘+click", "Add cursor"),
        ("CMD+Comma  Settings", "⌘Comma", "Settings"),
        ("CMD+Up/Down  Move", "⌘Up/Down", "Move"),
        ("CMD+F5  Run", "⌘F5", "Run"),
        ("CMD+K CMD+S  Save all", "⌘K ⌘S", "Save all"),
        ("Home  Start of line", "↖", "Start of line"),
        ("⌘1-9            Focus tab", "⌘1-9", "Focus tab"),
        ("CMD+-  Zoom out", "⌘-", "Zoom out"),
        ("X Toggle", "X", "Toggle"),
    ])
    func lines(_ line: String, _ shortcut: String, _ action: String) {
        let parsed = ShortcutLineParser.parse(line)
        #expect(parsed?.shortcut == shortcut)
        #expect(parsed?.action == action)
    }

    @Test(arguments: ["lonely", "", "   ", "|"])
    func unsplittable(_ line: String) {
        #expect(ShortcutLineParser.parse(line) == nil)
    }
}

@Suite struct AppResolverTests {
    @Test func forms() {
        #expect(AppResolver.resolve("com.figma.Desktop") == AppTarget(bundleId: "com.figma.Desktop", nameKey: "com.figma.desktop"))
        #expect(AppResolver.resolve("draw.io") == AppTarget(bundleId: "draw.io", nameKey: "draw.io"))
        #expect(AppResolver.resolve("Figma") == AppTarget(bundleId: nil, nameKey: "figma"))
        #expect(AppResolver.resolve("Notion.app") == AppTarget(bundleId: nil, nameKey: "notion"))
        #expect(AppResolver.resolve("/Nowhere/Adobe Photoshop 2024/Adobe Photoshop 2024.app") == AppTarget(bundleId: nil, nameKey: "adobe photoshop"))
        #expect(AppResolver.resolve("/System/Applications/TextEdit.app") == AppTarget(bundleId: "com.apple.TextEdit", nameKey: nil))
    }

    @Test func nameKeys() {
        #expect(AppResolver.nameKey("Sublime Text") == "sublime text")
        #expect(AppResolver.nameKey("Adobe Photoshop 2025.app") == "adobe photoshop")
        #expect(AppResolver.nameKey("Things 3") == "things 3")
        #expect(AppResolver.nameKey("2024") == "2024")
    }
}
