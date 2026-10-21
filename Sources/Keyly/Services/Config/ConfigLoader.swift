import Cocoa

struct ConfigSnapshot: Equatable {
    var settings = KeylySettings.defaults
    var sheets: [ShortcutSheet] = []
    var globalSheets: [ShortcutSheet] = []
    var diagnostics: [ConfigDiagnostic] = []

    func sheets(for app: NSRunningApplication) -> [ShortcutSheet] {
        let bundleId = app.bundleIdentifier?.lowercased()
        let nameKeys = AppResolver.nameKeys(for: app)
        return sheets.filter { sheet in
            guard let target = sheet.target else { return false }
            if let id = target.bundleId?.lowercased(), id == bundleId { return true }
            return target.nameKey.map(nameKeys.contains) ?? false
        }
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
        var candidatesByName: [String: [URL]] = [:]
        for directory in [templatesDirectory, configDirectory] {
            for file in sheetFiles(in: directory) {
                let name = file.lastPathComponent.lowercased()
                let known = candidatesByName[name] ?? []
                if known.contains(where: { $0.resolvingSymlinksInPath() == file.resolvingSymlinksInPath() }) { continue }
                candidatesByName[name] = known + [file]
            }
        }

        let previousByFile = Dictionary((previous.sheets + previous.globalSheets).compactMap { sheet in
            sheet.sourceFile.map { ($0, sheet) }
        }) { first, _ in first }

        for name in candidatesByName.keys.sorted() {
            let candidates = (candidatesByName[name] ?? []).sorted { modificationDate($0) > modificationDate($1) }
            let isGlobal = name == globalFileName

            var chosen: (file: URL, sheet: ShortcutSheet)?
            var failures: [ConfigDiagnostic] = []
            for file in candidates where chosen == nil {
                switch ConfigText.read(file) {
                case .text(let text):
                    let parsed = SheetParser.parse(text, defaultName: file.deletingPathExtension().lastPathComponent, isGlobal: isGlobal)
                    diagnostics += parsed.diagnostics.map { $0.in(file) }
                    var sheet = parsed.sheet
                    sheet.sourceFile = file
                    sheet.target = sheet.app.map(AppResolver.resolve)
                    chosen = (file, sheet)
                case .missing:
                    continue
                case .failed(let diagnostic):
                    failures.append(diagnostic)
                }
            }
            diagnostics += failures

            if chosen == nil, let kept = candidates.lazy.compactMap({ previousByFile[$0] }).first, let file = kept.sourceFile {
                chosen = (file, kept)
            }
            guard let (usedFile, sheet) = chosen else { continue }
            for other in candidates where other != usedFile && !failures.contains(where: { $0.file == other }) {
                diagnostics.append(ConfigDiagnostic(file: other, line: nil, message: "Not used: the \(usedFile.lastPathComponent) in \(usedFile.deletingLastPathComponent().lastPathComponent)/ is used instead"))
            }

            if isGlobal {
                snapshot.globalSheets.append(sheet)
            } else if sheet.target != nil {
                snapshot.sheets.append(sheet)
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
            at: directory.resolvingSymlinksInPath(),
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
