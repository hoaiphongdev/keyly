import Foundation
import Testing
@testable import Keyly

/// Every template shipped in templates/ must load without a single diagnostic
@Suite struct TemplateTests {
    static let templatesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("templates")

    static let files = ((try? FileManager.default.contentsOfDirectory(at: templatesDirectory, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "keyly" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

    @Test func templatesExist() {
        #expect(Self.files.count >= 30)
    }

    @Test(arguments: files)
    func templateParsesCleanly(_ file: URL) throws {
        let text = ConfigText.decode(try Data(contentsOf: file))
        let result = SheetParser.parse(text, defaultName: file.lastPathComponent)
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.summary))")
        #expect(result.sheet.app != nil)
        #expect(!result.sheet.shortcuts.isEmpty)
    }

    @Test func markdownKeysSurvive() throws {
        func shortcuts(_ name: String) throws -> [String] {
            let text = ConfigText.decode(try Data(contentsOf: Self.templatesDirectory.appendingPathComponent(name)))
            return SheetParser.parse(text, defaultName: name).sheet.shortcuts.map(\.shortcut)
        }
        let evernote = try shortcuts("evernote.keyly")
        #expect(["#", "##", "###", ">"].allSatisfy(evernote.contains))
        let notion = try shortcuts("notion.keyly")
        #expect(["# + Space", "## + Space", "### + Space", "> + Space"].allSatisfy(notion.contains))
        #expect(try shortcuts("illustrator.keyly").contains(">"))
        #expect(try shortcuts("illustrator.keyly").contains("\\"))
        #expect(try shortcuts("lightroom-classic.keyly").filter { $0 == "\\" }.count == 2)
    }
}

@Suite struct ConfigLoaderTests {
    private func makeFolder() throws -> (config: URL, templates: URL) {
        let config = FileManager.default.temporaryDirectory.appendingPathComponent("keyly-tests-\(UUID().uuidString)")
        let templates = config.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
        return (config, templates)
    }

    @Test func loadsIndexesAndOverrides() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.config) }

        try "# App: com.example.a\nCMD+A  From template".write(to: folder.templates.appendingPathComponent("a.keyly"), atomically: true, encoding: .utf8)
        try "# App: com.example.a\nCMD+B  From user".write(to: folder.config.appendingPathComponent("A.KEYLY"), atomically: true, encoding: .utf8)
        try "# App: Some App 2024\nCMD+C  By name".write(to: folder.templates.appendingPathComponent("b.keyly"), atomically: true, encoding: .utf8)
        try "CMD+Q  Quit".write(to: folder.templates.appendingPathComponent("global.keyly"), atomically: true, encoding: .utf8)
        try "no app here".write(to: folder.templates.appendingPathComponent("c.keyly"), atomically: true, encoding: .utf8)
        try "ignored".write(to: folder.templates.appendingPathComponent("._a.keyly"), atomically: true, encoding: .utf8)
        try "super_key = ctrl+k\nbogus = 1".write(to: folder.config.appendingPathComponent("setting.conf"), atomically: true, encoding: .utf8)

        let snapshot = ConfigLoader.load(configDirectory: folder.config, templatesDirectory: folder.templates, previous: ConfigSnapshot())

        #expect(snapshot.settings.trigger.label == "⌃K")
        #expect(snapshot.sheets.count == 2)
        #expect(snapshot.sheetsByBundleId["com.example.a"].map { $0.map { snapshot.sheets[$0].shortcuts[0].action } } == ["From user"])
        #expect(snapshot.sheetsByName["some app"]?.count == 1)
        #expect(snapshot.globalSheets.first?.shortcuts.first?.action == "Quit")
        // c.keyly has no app, setting.conf has an unknown name
        #expect(snapshot.diagnostics.count == 2)
        #expect(snapshot.diagnostics.allSatisfy { $0.file != nil })
    }

    @Test func unreadableFileKeepsThePreviousVersion() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder.config) }

        let file = folder.templates.appendingPathComponent("a.keyly")
        try "# App: com.example.a\nCMD+A  Works".write(to: file, atomically: true, encoding: .utf8)
        let first = ConfigLoader.load(configDirectory: folder.config, templatesDirectory: folder.templates, previous: ConfigSnapshot())

        // Too big to read: the sheet that worked a moment ago stays
        try Data(count: ConfigText.maxFileSize + 1).write(to: file)
        let second = ConfigLoader.load(configDirectory: folder.config, templatesDirectory: folder.templates, previous: first)

        #expect(second.sheets.first?.shortcuts.first?.action == "Works")
        #expect(second.diagnostics.count == 1)
    }

    @Test func missingFolderIsFine() {
        let nowhere = URL(fileURLWithPath: "/nonexistent/keyly")
        let snapshot = ConfigLoader.load(configDirectory: nowhere, templatesDirectory: nowhere, previous: ConfigSnapshot())
        #expect(snapshot.settings == .defaults)
        #expect(snapshot.sheets.isEmpty)
        #expect(snapshot.diagnostics.isEmpty)
    }
}
