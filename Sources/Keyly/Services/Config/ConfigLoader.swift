import Cocoa

/// Everything read from `~/.config/keyly`, built off the main thread and swapped in at once.
/// The key path and the overlay only read from it; they never touch the file system.
struct ConfigSnapshot {
    var settings = KeylySettings.defaults
    /// App sheets in load order
    var sheets: [ShortcutSheet] = []
    var globalSheets: [ShortcutSheet] = []
    var diagnostics: [ConfigDiagnostic] = []
    var sheetsByBundleId: [String: [Int]] = [:]
    var sheetsByName: [String: [Int]] = [:]

    /// Sheets for the frontmost app, by bundle id first, then by app name
    func sheets(for app: NSRunningApplication) -> [ShortcutSheet] {
        var indexes = app.bundleIdentifier.flatMap { sheetsByBundleId[$0] } ?? []
        for key in AppResolver.nameKeys(for: app) {
            indexes += sheetsByName[key] ?? []
        }
        return Array(Set(indexes)).sorted().map { sheets[$0] }
    }
}

enum ConfigLoader {
    static let fileExtension = "keyly"
    static let globalFileName = AppConstants.globalTemplateFileName

    /// - Parameter previous: used when a file can't be read right now (e.g. mid-save),
    ///   so a bad moment never wipes a sheet that was working
    static func load(configDirectory: URL, templatesDirectory: URL, previous: ConfigSnapshot) -> ConfigSnapshot {
        var snapshot = ConfigSnapshot()
        var diagnostics: [ConfigDiagnostic] = []

        // Settings
        let settingsFile = configDirectory.appendingPathComponent(SettingsParser.fileName)
        switch ConfigText.read(settingsFile) {
        case .text(let text):
            let (settings, settingsDiagnostics) = SettingsParser.parse(text)
            snapshot.settings = settings
            diagnostics += settingsDiagnostics.map { $0.in(settingsFile) }
        case .missing:
            break
        case .failed(let diagnostic):
            snapshot.settings = previous.settings
            diagnostics.append(diagnostic)
        }

        // Sheets: templates/ first; a file with the same name directly in ~/.config/keyly replaces it
        var filesByName: [String: URL] = [:]
        for directory in [templatesDirectory, configDirectory] {
            for file in sheetFiles(in: directory) {
                filesByName[file.lastPathComponent.lowercased()] = file
            }
        }

        let previousByFile = Dictionary((previous.sheets + previous.globalSheets).compactMap { sheet in
            sheet.sourceFile.map { ($0, sheet) }
        }) { first, _ in first }

        for name in filesByName.keys.sorted() {
            guard let file = filesByName[name] else { continue }
            let isGlobal = name == globalFileName

            var sheet: ShortcutSheet
            switch ConfigText.read(file) {
            case .text(let text):
                let parsed = SheetParser.parse(text, defaultName: file.deletingPathExtension().lastPathComponent, isGlobal: isGlobal)
                diagnostics += parsed.diagnostics.map { $0.in(file) }
                sheet = parsed.sheet
                sheet.sourceFile = file
                sheet.target = sheet.app.map(AppResolver.resolve)
            case .missing:
                continue
            case .failed(let diagnostic):
                diagnostics.append(diagnostic)
                guard let kept = previousByFile[file] else { continue }
                sheet = kept
            }

            if isGlobal {
                snapshot.globalSheets.append(sheet)
            } else if let target = sheet.target {
                let index = snapshot.sheets.count
                snapshot.sheets.append(sheet)
                if let bundleId = target.bundleId { snapshot.sheetsByBundleId[bundleId, default: []].append(index) }
                if let nameKey = target.nameKey { snapshot.sheetsByName[nameKey, default: []].append(index) }
            }
        }

        snapshot.diagnostics = diagnostics
        return snapshot
    }

    /// `.keyly` files in one folder (any case), without hidden files such as `._name.keyly`
    private static func sheetFiles(in directory: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { $0.pathExtension.lowercased() == fileExtension }
    }
}

private extension ConfigDiagnostic {
    func `in`(_ file: URL) -> ConfigDiagnostic {
        var diagnostic = self
        diagnostic.file = file
        return diagnostic
    }
}
