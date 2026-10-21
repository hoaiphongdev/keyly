import Foundation
import Cocoa

enum EditorType: String, CaseIterable {
    case vscode = "vscode"
    case neovim = "neovim"
    case textEdit = "textedit"

    var displayName: String {
        switch self {
        case .vscode: return "VS Code"
        case .neovim: return "Neovim"
        case .textEdit: return "TextEdit"
        }
    }
}

final class ConfigManager {
    static let shared = ConfigManager()

    /// Read on the main thread only; replaced as a whole after each reload
    private(set) var snapshot = ConfigSnapshot()
    private var fileWatcher: FileWatcher?
    private let loadQueue = DispatchQueue(label: "com.keyly.config", qos: .utility)

    private let editorPreferenceKey = "KeylyPreferredEditor"

    var onConfigReloaded: (() -> Void)?
    var onSettingsReloaded: (() -> Void)?

    private init() {}

    var preferredEditor: EditorType? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: editorPreferenceKey) else { return nil }
            return EditorType(rawValue: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: editorPreferenceKey)
        }
    }

    let configDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/keyly", isDirectory: true)

    var templatesDirectory: URL {
        configDirectory.appendingPathComponent("templates", isDirectory: true)
    }

    var settings: KeylySettings { snapshot.settings }
    var diagnostics: [ConfigDiagnostic] { snapshot.diagnostics }
    var globalSheets: [ShortcutSheet] { snapshot.globalSheets }

    func sheets(for app: NSRunningApplication) -> [ShortcutSheet] {
        snapshot.sheets(for: app)
    }

    /// First load at launch, synchronous so the trigger is known before keys are monitored
    func loadInitial() {
        ensureDirectories()
        createDefaultSettingsIfNeeded()
        publish(loadSnapshot(previous: snapshot))
    }

    /// Parses on a background queue and swaps the result in on the main thread
    func reload() {
        let previous = snapshot
        loadQueue.async { [weak self] in
            guard let self else { return }
            let next = self.loadSnapshot(previous: previous)
            DispatchQueue.main.async {
                let settingsChanged = next.settings != self.snapshot.settings
                self.publish(next)
                self.onConfigReloaded?()
                if settingsChanged { self.onSettingsReloaded?() }
            }
        }
    }

    private func loadSnapshot(previous: ConfigSnapshot) -> ConfigSnapshot {
        let start = CFAbsoluteTimeGetCurrent()
        let next = ConfigLoader.load(configDirectory: configDirectory, templatesDirectory: templatesDirectory, previous: previous)
        let milliseconds = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        ConfigLog.info("Loaded \(next.sheets.count) sheet(s), \(next.globalSheets.count) global, trigger \(next.settings.trigger.label) in \(milliseconds) ms")
        return next
    }

    private func publish(_ next: ConfigSnapshot) {
        snapshot = next
        ConfigLog.report(next.diagnostics)
    }

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(at: templatesDirectory, withIntermediateDirectories: true)
    }

    func startWatching() {
        // Recursive, so templates/ is covered too
        fileWatcher = FileWatcher(paths: [configDirectory.path]) { [weak self] in
            self?.reload()
        }
        fileWatcher?.start()
    }

    func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }

    func openConfigFolder() {
        ensureDirectories()
        createExamplesIfNeeded()
        open(configDirectory, line: nil)
    }

    /// Opens a config file in the preferred editor, at the line with the problem when the editor supports it
    func openFile(_ file: URL, line: Int?) {
        open(file, line: line)
    }

    private func open(_ url: URL, line: Int?) {
        if let editor = preferredEditor ?? pickEditor() {
            open(url, line: line, with: editor)
        }
    }

    private func pickEditor() -> EditorType? {
        let alert = NSAlert()
        alert.messageText = "Choose Editor"
        alert.informativeText = "Select your preferred editor to open config files. This will be saved and won't be asked again."
        alert.alertStyle = .informational

        for editor in EditorType.allCases {
            alert.addButton(withTitle: editor.displayName)
        }

        alert.window.level = .screenSaver
        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()

        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard index >= 0 && index < EditorType.allCases.count else { return nil }

        let selectedEditor = EditorType.allCases[index]
        preferredEditor = selectedEditor
        return selectedEditor
    }

    private func open(_ url: URL, line: Int?, with editor: EditorType) {
        let path = url.path
        let isFolder = url.hasDirectoryPath

        switch editor {
        case .vscode:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = isFolder || line == nil ? ["code", path] : ["code", "--goto", "\(path):\(line ?? 1)"]
            try? process.run()

        case .neovim:
            let target = isFolder ? "cd \(shellQuoted(path)) && nvim ." : "nvim \(line.map { "+\($0) " } ?? "")\(shellQuoted(path))"
            runTerminalScript("#!/bin/bash\n\(target)\n")

        case .textEdit:
            if isFolder {
                NSWorkspace.shared.open(url)
            } else {
                let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
                NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runTerminalScript(_ content: String) {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("keyly-open-config.command")

        do {
            try content.write(to: tempScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
            NSWorkspace.shared.open(tempScript)
        } catch {
            ConfigLog.logger.error("Failed to open config: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Starter files

    /// setting.conf is written at launch when missing, every line commented out: the defaults
    /// apply and every option is right there to uncomment. An existing file is never touched.
    private func createDefaultSettingsIfNeeded() {
        let file = configDirectory.appendingPathComponent(SettingsParser.fileName)
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try? Self.defaultSettingsContent.write(to: file, atomically: true, encoding: .utf8)
    }

    static let defaultSettingsContent = """
    # Keyly settings
    # Remove the # in front of a line to change it. Changes apply as soon as you save.
    # A value Keyly can't read falls back to its default; problems show in the ⚙︎ menu.

    # Key that opens Keyly: capslock, cmd, ctrl+k, cmd+shift+k, option+space, ⌃⌥K …
    # super_key = capslock

    # press: tap the key press_count times in a row. hold: keep it down for hold_duration.
    # Caps Lock can only be pressed.
    # trigger_type = press

    # Taps in a row, 1 to 4
    # press_count = 2

    # How long to hold, 0.1s to 3s: 0.5, 0.5s or 500ms
    # hold_duration = 0.5

    # Widest the window gets, as a share of the screen: 0.1 to 1.0, or 70%
    # screen_width_ratio = 0.7

    """

    /// Example sheets for "Open Config Folder", each written only if missing
    private func createExamplesIfNeeded() {
        createDefaultSettingsIfNeeded()

        let exampleTemplateFile = templatesDirectory.appendingPathComponent("example.keyly")
        if !FileManager.default.fileExists(atPath: exampleTemplateFile.path) {
            let exampleContent = """
            # Sheet Name: Example Shortcuts
            # App: Safari
            # Hide Default: false

            [Navigation]
            CMD+L       Open Location
            CMD+T       New Tab
            CMD+W       Close Tab
            CMD+SHIFT+T Reopen Last Tab

            [Bookmarks]
            CMD+D       Add Bookmark
            CMD+OPT+B   Show Bookmarks

            [View]
            CMD++       Zoom In
            CMD+-       Zoom Out
            CMD+0       Actual Size
            """
            try? exampleContent.write(to: exampleTemplateFile, atomically: true, encoding: .utf8)
        }

        let globalTemplateFile = templatesDirectory.appendingPathComponent(AppConstants.globalTemplateFileName)
        if !FileManager.default.fileExists(atPath: globalTemplateFile.path) {
            let globalContent = """
            # Global Shortcuts - Available in all applications
            # These shortcuts will appear at the top of every app's shortcut list

            [System]
            > System-wide shortcuts that work everywhere
            CMD+SPACE       Spotlight Search
            CMD+TAB         App Switcher
            CMD+Q           Quit Application
            CMD+W           Close Window

            [Text Editing]
            > Universal text editing shortcuts
            CMD+C           Copy
            CMD+V           Paste
            CMD+X           Cut
            CMD+Z           Undo
            CMD+A           Select All
            CMD+F           Find
            """
            try? globalContent.write(to: globalTemplateFile, atomically: true, encoding: .utf8)
        }
    }
}
