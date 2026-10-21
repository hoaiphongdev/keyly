import Foundation
import Testing
@testable import Keyly

@Suite struct EditorTests {
    @Test func vscodeGoesToTheLine() {
        #expect(ConfigManager.vscodeArguments(path: "/a b/x.keyly", isFolder: false, line: 12) == ["code", "--goto", "/a b/x.keyly:12"])
        #expect(ConfigManager.vscodeArguments(path: "/a b/x.keyly", isFolder: false, line: nil) == ["code", "/a b/x.keyly"])
        #expect(ConfigManager.vscodeArguments(path: "/cfg", isFolder: true, line: 3) == ["code", "/cfg"])
    }

    @Test func editorPathFindsHomebrewAndLocalBin() {
        let launchd = ConfigManager.editorEnvironment(["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])["PATH"]
        #expect(launchd == "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin")
        #expect(ConfigManager.editorEnvironment(["PATH": "/fake:/usr/local/bin"])["PATH"] == "/fake:/usr/local/bin:/opt/homebrew/bin")
        #expect(ConfigManager.editorEnvironment([:])["PATH"]?.hasSuffix("/usr/local/bin:/opt/homebrew/bin") == true)
    }

    @Test(arguments: [("/tmp/it's here/a b.keyly", 7 as Int?), ("/tmp/plain.keyly", nil)])
    func neovimScriptQuotesThePath(_ path: String, _ line: Int?) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("keyly-nvim-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fakeNvim = dir.appendingPathComponent("nvim")
        let record = dir.appendingPathComponent("args")
        try "#!/bin/bash\nprintf '%s\\n' \"$@\" > '\(record.path)'\n".write(to: fakeNvim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeNvim.path)

        let script = dir.appendingPathComponent("open.command")
        try ConfigManager.neovimScript(path: path, isFolder: false, line: line).write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.environment = ["PATH": "\(dir.path):/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()

        let args = try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(args == (line.map { ["+\($0)"] } ?? []) + [path])
    }

    @Test func neovimFolderScript() {
        #expect(ConfigManager.neovimScript(path: "/x y", isFolder: true, line: 4) == "#!/bin/bash\ncd '/x y' && nvim .\n")
    }
}
