import Foundation

/// Parses a `.keyly` file in one pass. A line it can't read is skipped with a diagnostic;
/// the rest of the sheet still loads.
///
/// - `# App: …`, `# Sheet Name: …`, `# Hide Default: …`, `# Group: …` — directives (any case)
/// - `# anything else` — comment
/// - `[Category]` — start a category, `> text` — its description
/// - `\#`, `\[`, `\>` — a shortcut whose key starts with that character
/// - anything else — a shortcut line, see `ShortcutLineParser`
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

            if line.hasPrefix("\\") {
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
                    break // a comment that happens to contain a colon
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
            report(nil, "No # App: line, so this sheet isn't shown. Add one like \"# App: Figma\"")
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

    /// `# App: Figma` → ("app", "Figma"). Names are matched without case.
    private static func directive(in line: String) -> (String, String)? {
        let body = line.drop { $0 == "#" }
        guard let colon = body.firstIndex(of: ":") else { return nil }
        let name = body[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard ["sheet name", "app", "hide default", "hide defaults", "group"].contains(name) else { return nil }
        return (name, body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }
}
