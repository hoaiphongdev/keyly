import Foundation

struct ShortcutSheet: Identifiable {
    let id: UUID
    let name: String
    let appPath: String
    let shortcuts: [ShortcutItem]
    let sourceFile: URL?
    
    init(id: UUID = UUID(), name: String, appPath: String, shortcuts: [ShortcutItem], sourceFile: URL? = nil) {
        self.id = id
        self.name = name
        self.appPath = appPath
        self.shortcuts = shortcuts
        self.sourceFile = sourceFile
    }
    
    /// Returns the bundle identifier for the app path if it exists
    var bundleIdentifier: String? {
        Bundle(path: appPath)?.bundleIdentifier
    }
}

