import Foundation

struct ShortcutSheet: Equatable {
    let name: String
    let app: String?
    let shortcuts: [ShortcutItem]
    let categoryDescriptions: [String: String]
    let groupDescriptions: [String: String]
    let hideDefaultShortcuts: Bool
    var sourceFile: URL?
    var target: AppTarget?
}
