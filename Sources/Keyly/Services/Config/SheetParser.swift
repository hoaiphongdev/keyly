import Foundation

enum SheetParser {
    static let maxDiagnosticsPerFile = 20

    static func parse(_ text: String, defaultName: String, isGlobal: Bool = false) -> (sheet: ShortcutSheet, diagnostics: [ConfigDiagnostic]) {
        let defaultCategory = isGlobal ? "Global" : "General"

        var name = defaultName
        var app: String?
        var hideDefault = false
        var shortcuts: [ShortcutItem] = []
        var categoryDescriptions: [String: String] = [:]
        var groupDescriptions: [String: String] = [:]
        var category = defaultCategory
        var group: String?
        var diagnostics: [ConfigDiagnostic] = []
        var skippedDiagnostics = 0

        func report(_ line: Int?, _ message: String) {
            if diagnostics.count < maxDiagnosticsPerFile {
                diagnostics.append(ConfigDiagnostic(line: line, message: message))
            } else {
                skippedDiagnostics += 1
            }
        }

        func addShortcut(_ line: String, at lineNumber: Int) {
            if let (shortcut, action) = ShortcutLineParser.parse(line) {
                shortcuts.append(ShortcutItem(category: category, action: action, shortcut: shortcut, group: group))
            } else {
                report(lineNumber, "Couldn't tell the shortcut from its description. Put two spaces or | between them")
            }
        }

        for (index, rawLine) in ConfigText.lines(text).enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("\\"), let next = line.dropFirst().first, "#[>\\".contains(next) {
                addShortcut(String(line.dropFirst()), at: lineNumber)
                continue
            }

            if line.hasPrefix("#") {
                guard let (directive, value) = directive(in: line) else { continue }
                switch directive {
                case "sheet name":
                    if !value.isEmpty { name = value }
                case "app":
                    if !isGlobal { app = value.isEmpty ? nil : value }
                case "hide default", "hide defaults":
                    if !isGlobal { hideDefault = ["true", "yes", "on", "1"].contains(value.lowercased()) }
                case "group":
                    let groupName = value.components(separatedBy: " - ")[0].trimmingCharacters(in: .whitespaces)
                    category = defaultCategory
                    if ["", "none", "empty"].contains(groupName.lowercased()) {
                        group = nil
                    } else {
                        group = groupName
                        let description = value.components(separatedBy: " - ").dropFirst()
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .first { !$0.isEmpty && !$0.hasPrefix("Size:") }
                        if let description { groupDescriptions[groupName] = description }
                    }
                default:
                    break
                }
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                let categoryName = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
                if categoryName.isEmpty {
                    report(lineNumber, "Empty category name, using \(defaultCategory)")
                }
                category = categoryName.isEmpty ? defaultCategory : categoryName
                continue
            }

            if line.hasPrefix(">") {
                let description = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if !description.isEmpty { categoryDescriptions[category] = description }
                continue
            }

            addShortcut(line, at: lineNumber)
        }

        if !isGlobal && app == nil {
            diagnostics.insert(ConfigDiagnostic(line: nil, message: "No # App: line, so this sheet isn't shown. Add one like \"# App: Figma\""), at: 0)
        }
        if skippedDiagnostics > 0 {
            diagnostics.append(ConfigDiagnostic(line: nil, message: "\(skippedDiagnostics) more problem(s) not listed"))
        }

        let sheet = ShortcutSheet(
            name: name,
            app: app,
            shortcuts: shortcuts,
            categoryDescriptions: categoryDescriptions,
            groupDescriptions: groupDescriptions,
            hideDefaultShortcuts: hideDefault
        )
        return (sheet, diagnostics)
    }

    private static func directive(in line: String) -> (String, String)? {
        let body = line.dropFirst()
        guard !body.hasPrefix("#"), let colon = body.firstIndex(of: ":") else { return nil }
        let name = body[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard ["sheet name", "app", "hide default", "hide defaults", "group"].contains(name) else { return nil }
        return (name, body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }
}
