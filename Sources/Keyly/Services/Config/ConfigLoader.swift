import Cocoa

struct ConfigSnapshot {
    var settings = KeylySettings.defaults
    var sheets: [ShortcutSheet] = []
    var globalSheets: [ShortcutSheet] = []
    var diagnostics: [ConfigDiagnostic] = []
    var sheetsByBundleId: [String: [Int]] = [:]
    var sheetsByName: [String: [Int]] = [:]

    func sheets(for app: NSRunningApplication) -> [ShortcutSheet] {
        var indexes = app.bundleIdentifier.flatMap { sheetsByBundleId[$0.lowercased()] } ?? []
        for key in AppResolver.nameKeys(for: app) {
            indexes += sheetsByName[key] ?? []
        }
        return Array(Set(indexes)).sorted().map { sheets[$0] }
    }
}

enum ConfigLoader {
    static let fileExtension = "keyly"
    static let globalFileName = AppConstants.globalTemplateFileName

    static func load(configDirectory: URL, templatesDirectory: URL, previous: ConfigSnapshot) -> ConfigSnapshot {
        var snapshot = ConfigSnapshot()
        var diagnostics: [ConfigDiagnostic] = []

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

        // templates/ is the documented home; .keyly files placed directly in ~/.config/keyly/
        // (older docs and install-templates.sh put them there) are loaded too.
        var filesByName: [String: URL] = [:]
        for directory in [templatesDirectory, configDirectory] {
            for file in sheetFiles(in: directory) {
                let name = file.lastPathComponent.lowercased()
                guard let existing = filesByName[name] else {
                    filesByName[name] = file
                    continue
                }
                let (kept, ignored) = modificationDate(existing) >= modificationDate(file) ? (existing, file) : (file, existing)
                filesByName[name] = kept
                diagnostics.append(ConfigDiagnostic(file: ignored, line: nil, message: "Not used: a newer \(kept.lastPathComponent) is in \(kept.deletingLastPathComponent().lastPathComponent)/"))
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
                if let bundleId = target.bundleId { snapshot.sheetsByBundleId[bundleId.lowercased(), default: []].append(index) }
                if let nameKey = target.nameKey { snapshot.sheetsByName[nameKey, default: []].append(index) }
            }
        }

        snapshot.diagnostics = diagnostics
        return snapshot
    }

    private static func modificationDate(_ file: URL) -> Date {
        (try? file.resolvingSymlinksInPath().resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

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
