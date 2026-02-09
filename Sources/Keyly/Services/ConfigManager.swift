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
    
    private(set) var customSheets: [ShortcutSheet] = []
    private(set) var globalShortcuts: [ShortcutItem] = []
    private var fileWatcher: FileWatcher?
    
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
    
    var configDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keylyDir = home.appendingPathComponent(".config/keyly", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: keylyDir, withIntermediateDirectories: true)
        
        return keylyDir
    }
    
    var templatesDirectory: URL {
        let templatesDir = configDirectory.appendingPathComponent("templates", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: templatesDir, withIntermediateDirectories: true)
        
        return templatesDir
    }
    
    func loadAllSheets() {
        customSheets.removeAll()
        globalShortcuts.removeAll()
        
        let fileManager = FileManager.default
        
        guard let files = try? fileManager.contentsOfDirectory(at: templatesDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files where file.pathExtension == "keyly" {
            if file.lastPathComponent == AppConstants.globalTemplateFileName {
                loadGlobalShortcuts(from: file)
            } else {
                if let sheet = parseSheetFile(at: file) {
                    customSheets.append(sheet)
                }
            }
        }
        
        print("[Keyly] Loaded \(customSheets.count) custom sheet(s)")
        print("[Keyly] Loaded \(globalShortcuts.count) global shortcut(s)")
    }
    
    func reload() {
        loadAllSheets()
        SettingsManager.shared.reloadSettings()
        onConfigReloaded?()
        onSettingsReloaded?()
    }
    
    private func parseSheetFile(at url: URL) -> ShortcutSheet? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("[Keyly] Warning: Could not read file '\(url.lastPathComponent)'")
            return nil
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[Keyly] Warning: File '\(url.lastPathComponent)' is empty")
            return nil
        }
        
        var name = url.deletingPathExtension().lastPathComponent
        var appPath = ""
        var shortcuts: [ShortcutItem] = []
        var categoryDescriptions: [String: String] = [:]
        var groupDescriptions: [String: String] = [:]
        var currentCategory = "General"
        var currentGroup: String? = nil
        var hideDefaultShortcuts = false
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("# Sheet Name:") {
                name = trimmed.replacingOccurrences(of: "# Sheet Name:", with: "").trimmingCharacters(in: .whitespaces)
                continue
            }
            
            if trimmed.hasPrefix("# App:") {
                appPath = trimmed.replacingOccurrences(of: "# App:", with: "").trimmingCharacters(in: .whitespaces)
                continue
            }
            
            if trimmed.hasPrefix("# Hide Default:") {
                let hideValue = trimmed.replacingOccurrences(of: "# Hide Default:", with: "").trimmingCharacters(in: .whitespaces).lowercased()
                hideDefaultShortcuts = ["true", "1", "yes", "on"].contains(hideValue)
                continue
            }
            
            if trimmed.hasPrefix("# Group:") {
                let groupInfo = trimmed.replacingOccurrences(of: "# Group:", with: "").trimmingCharacters(in: .whitespaces)
                if !groupInfo.isEmpty {
                    let components = groupInfo.components(separatedBy: " - ")
                    if components.count >= 1 {
                        let groupName = components[0].trimmingCharacters(in: .whitespaces)
                        if !groupName.isEmpty {
                            currentGroup = groupName
                            if components.count >= 2 {
                                let description = components[1].trimmingCharacters(in: .whitespaces)
                                if !description.isEmpty {
                                    groupDescriptions[groupName] = description
                                }
                            }
                        } else {
                            print("[Keyly] Warning: Empty group name in '\(url.lastPathComponent)'")
                        }
                    }
                } else {
                    print("[Keyly] Warning: Empty group directive in '\(url.lastPathComponent)'")
                }
                continue
            }
            
            if trimmed.hasPrefix("#") { continue }
            
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let categoryName = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !categoryName.isEmpty {
                    currentCategory = categoryName
                } else {
                    print("[Keyly] Warning: Empty category name in '\(url.lastPathComponent)', using 'General'")
                    currentCategory = "General"
                }
                continue
            }
            
            if trimmed.hasPrefix(">") {
                let desc = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !desc.isEmpty {
                    categoryDescriptions[currentCategory] = desc
                }
                continue
            }
            
            if let shortcut = parseShortcutLine(trimmed, category: currentCategory, group: currentGroup) {
                shortcuts.append(shortcut)
            }
        }
        
        guard !appPath.isEmpty else {
            print("[Keyly] Warning: Sheet '\(name)' has no app path defined")
            return nil
        }
        
        return ShortcutSheet(name: name, appPath: appPath, shortcuts: shortcuts, categoryDescriptions: categoryDescriptions, sourceFile: url, hideDefaultShortcuts: hideDefaultShortcuts, groupDescriptions: groupDescriptions)
    }
    
    private func parseShortcutLine(_ line: String, category: String, group: String? = nil) -> ShortcutItem? {
        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        guard parts.count >= 2 else { 
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                print("[Keyly] Warning: Invalid shortcut line format: '\(line)'")
            }
            return nil 
        }
        
        let rawShortcut = parts[0]
        let action = parts.dropFirst().joined(separator: " ")
        
        guard !rawShortcut.isEmpty && !action.isEmpty else {
            print("[Keyly] Warning: Empty shortcut or action in line: '\(line)'")
            return nil
        }
        
        let shortcut = normalizeShortcut(rawShortcut)
        
        guard shortcut.contains(where: { Modifier.allCharacters.contains($0) }) else {
            print("[Keyly] Warning: No valid modifier found in shortcut: '\(rawShortcut)'")
            return nil
        }
        
        return ShortcutItem(category: category, action: action, shortcut: shortcut, group: group)
    }
    
    private func normalizeShortcut(_ raw: String) -> String {
        guard !raw.isEmpty else {
            print("[Keyly] Warning: Empty shortcut string")
            return raw
        }
        
        var result = raw.uppercased()
        
        for (patterns, symbol) in ShortcutMapping.modifiersWithSeparator {
            for pattern in patterns {
                result = result.replacingOccurrences(of: pattern, with: symbol)
            }
        }
        
        for (patterns, symbol) in ShortcutMapping.modifiersDirect {
            for pattern in patterns {
                result = result.replacingOccurrences(of: pattern, with: symbol)
            }
        }
        
        for (key, symbol) in ShortcutMapping.specialKeys {
            result = result.replacingOccurrences(of: key, with: symbol)
        }
        
        return result
    }
    
    func startWatching() {
        let watchPaths = [
            templatesDirectory.path,
            configDirectory.path
        ]
        fileWatcher = FileWatcher(paths: watchPaths) { [weak self] in
            self?.reload()
        }
        fileWatcher?.start()
    }
    
    func stopWatching() {
        fileWatcher?.stop()
        fileWatcher = nil
    }
    
    func sheets(for bundleIdentifier: String) -> [ShortcutSheet] {
        customSheets.filter { $0.bundleIdentifier == bundleIdentifier }
    }
    
    private func loadGlobalShortcuts(from url: URL) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("[Keyly] Warning: Could not read global shortcuts file '\(url.lastPathComponent)'")
            return
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[Keyly] Warning: Global shortcuts file '\(url.lastPathComponent)' is empty")
            return
        }
        
        var shortcuts: [ShortcutItem] = []
        var currentCategory = "Global"
        var currentGroup: String? = nil
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("# Group:") {
                let groupInfo = trimmed.replacingOccurrences(of: "# Group:", with: "").trimmingCharacters(in: .whitespaces)
                if !groupInfo.isEmpty {
                    let components = groupInfo.components(separatedBy: " - ")
                    if components.count >= 1 {
                        let groupName = components[0].trimmingCharacters(in: .whitespaces)
                        if !groupName.isEmpty {
                            currentGroup = groupName
                        } else {
                            print("[Keyly] Warning: Empty group name in global shortcuts")
                        }
                    }
                } else {
                    print("[Keyly] Warning: Empty group directive in global shortcuts")
                }
                continue
            }
            
            if trimmed.hasPrefix("#") { continue }
            
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let categoryName = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !categoryName.isEmpty {
                    currentCategory = categoryName
                } else {
                    print("[Keyly] Warning: Empty category name in global shortcuts, using 'Global'")
                    currentCategory = "Global"
                }
                continue
            }
            
            if trimmed.hasPrefix(">") { continue }
            
            if let shortcut = parseShortcutLine(trimmed, category: currentCategory, group: currentGroup) {
                shortcuts.append(shortcut)
            }
        }
        
        globalShortcuts = shortcuts
    }
    
    func openConfigFolder() {
        createExampleIfNeeded()
        
        if let editor = preferredEditor {
            openWithEditor(editor)
        } else {
            showEditorPicker()
        }
    }
    
    private func showEditorPicker() {
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
        guard index >= 0 && index < EditorType.allCases.count else { return }
        
        let selectedEditor = EditorType.allCases[index]
        preferredEditor = selectedEditor
        openWithEditor(selectedEditor)
    }
    
    private func openWithEditor(_ editor: EditorType) {
        let path = configDirectory.path
        
        switch editor {
        case .vscode:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["code", path]
            try? process.run()
            
        case .neovim:
            let scriptContent = """
            #!/bin/bash
            cd '\(path)'
            nvim .
            """
            runTerminalScript(scriptContent)
            
        case .textEdit:
            NSWorkspace.shared.open(configDirectory)
        }
    }
    
    private func runTerminalScript(_ content: String) {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("keyly-open-config.command")
        
        do {
            try content.write(to: tempScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
            NSWorkspace.shared.open(tempScript)
        } catch {
            print("[Keyly] Failed to open config: \(error)")
        }
    }
    
    private func createExampleIfNeeded() {
        // Create example template
        let exampleTemplateFile = templatesDirectory.appendingPathComponent("example.keyly")
        guard !FileManager.default.fileExists(atPath: exampleTemplateFile.path) else { return }
        
        let exampleContent = """
        # Sheet Name: Example Shortcuts
        # App: /Applications/Safari.app
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
        
        let globalTemplateFile = templatesDirectory.appendingPathComponent(AppConstants.globalTemplateFileName)
        guard !FileManager.default.fileExists(atPath: globalTemplateFile.path) else { return }
        
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
        
        // Create example config
        let exampleConfigFile = configDirectory.appendingPathComponent("setting.conf")
        guard !FileManager.default.fileExists(atPath: exampleConfigFile.path) else { return }
        
        let exampleConfigContent = """
        # Keyly Configuration File
        # Place this file at ~/.config/keyly/setting.conf

        # Super key configuration - can be single key or combinations:
        # Single keys: cmd, ctrl, alt, shift, fn, space, a, b, c, f1, etc.
        # Combinations: cmd+a, ctrl+shift+x, alt+space, fn+f12, etc.
        super_key=cmd+a
        trigger_type=hold

        # Hold settings (used when trigger_type = hold)
        hold_duration=0.5

        # Press settings (used when trigger_type = press)
        press_count=2
        """
        
        try? exampleConfigContent.write(to: exampleConfigFile, atomically: true, encoding: .utf8)
    }
}
