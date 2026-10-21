import Cocoa
import Testing
@testable import Keyly

@Suite struct PerformanceTests {
    @Test func triggerMatchingIsCheap() {
        let trigger = SettingsParser.parse("super_key = ctrl+shift+k").settings.trigger
        let flags: [NSEvent.ModifierFlags] = [[.control, .shift], [.command], [.control, .shift, .capsLock], []]
        var hits = 0
        let start = Date()
        for i in 0..<1_000_000 {
            if trigger.matchesKey(UInt16(i & 63), flags: flags[i & 3]) { hits += 1 }
            if !trigger.relevantModifiers(flags[i & 3]).isEmpty { hits += 1 }
        }
        let perCall = Date().timeIntervalSince(start) / 2_000_000
        #expect(hits > 0)
        #expect(perCall < 1e-6, "\(perCall * 1e9) ns per call")
        print("trigger matching: \(String(format: "%.1f", perCall * 1e9)) ns per call (debug build)")
    }

    @Test func allBundledTemplatesLoadFast() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keyly-perf-\(UUID().uuidString)")
        let templates = folder.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for file in TemplateTests.files {
            try FileManager.default.copyItem(at: file, to: templates.appendingPathComponent(file.lastPathComponent))
        }

        var best = Double.infinity
        var snapshot = ConfigSnapshot()
        for _ in 0..<5 {
            let start = Date()
            snapshot = ConfigLoader.load(configDirectory: folder, templatesDirectory: templates, previous: snapshot)
            best = min(best, Date().timeIntervalSince(start))
        }
        #expect(snapshot.sheets.count == TemplateTests.files.count)
        #expect(snapshot.diagnostics.isEmpty)
        #expect(best < 0.1, "\(best * 1000) ms")
        print("load \(snapshot.sheets.count) templates: \(String(format: "%.1f", best * 1000)) ms (debug build)")
    }
}
