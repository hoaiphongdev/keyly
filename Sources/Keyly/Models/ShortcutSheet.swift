import Foundation

/// One `.keyly` file. `global.keyly` has no app and shows in every app.
struct ShortcutSheet {
    let name: String
    /// The `# App:` value as written: a path, a bundle id or an app name
    let app: String?
    let shortcuts: [ShortcutItem]
    let categoryDescriptions: [String: String]
    let groupDescriptions: [String: String]
    let hideDefaultShortcuts: Bool
    var sourceFile: URL?
    /// Resolved from `app` when the sheet loads, never on the key path
    var target: AppTarget?
}
