import Foundation

struct ShortcutSheet: Identifiable {
    let id: UUID
    let name: String
    let appPath: String
    let shortcuts: [ShortcutItem]
    let categoryDescriptions: [String: String]
    let sourceFile: URL?
    let hideDefaultShortcuts: Bool
    let groupDescriptions: [String: String]
    let groupSizes: [String: Int]
    
    init(id: UUID = UUID(), name: String, appPath: String, shortcuts: [ShortcutItem], categoryDescriptions: [String: String] = [:], sourceFile: URL? = nil, hideDefaultShortcuts: Bool = false, groupDescriptions: [String: String] = [:], groupSizes: [String: Int] = [:]) {
        self.id = id
        self.name = name
        self.appPath = appPath
        self.shortcuts = shortcuts
        self.categoryDescriptions = categoryDescriptions
        self.sourceFile = sourceFile
        self.hideDefaultShortcuts = hideDefaultShortcuts
        self.groupDescriptions = groupDescriptions
        self.groupSizes = groupSizes
    }
    
    /// Returns the bundle identifier for the app path if it exists
    var bundleIdentifier: String? {
        Bundle(path: appPath)?.bundleIdentifier
    }
}

