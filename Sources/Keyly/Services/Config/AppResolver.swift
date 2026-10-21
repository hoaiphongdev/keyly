import Cocoa

struct AppTarget: Equatable {
    let bundleId: String?
    let nameKey: String?
}

enum AppResolver {
    static func resolve(_ raw: String) -> AppTarget {
        let value = raw.trimmingCharacters(in: .whitespaces)

        if value.contains("/") {
            let path = (value as NSString).expandingTildeInPath
            if let bundleId = Bundle(path: path)?.bundleIdentifier {
                return AppTarget(bundleId: bundleId, nameKey: nil)
            }
            return AppTarget(bundleId: nil, nameKey: nameKey((path as NSString).lastPathComponent))
        }

        if looksLikeBundleId(value) {
            return AppTarget(bundleId: value, nameKey: nameKey(value))
        }
        return AppTarget(bundleId: nil, nameKey: nameKey(value))
    }

    static func nameKeys(for app: NSRunningApplication) -> [String] {
        let names = [app.bundleURL?.lastPathComponent, app.localizedName].compactMap { $0 }
        var keys: [String] = []
        for key in names.map(nameKey) where !key.isEmpty && !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    static func nameKey(_ name: String) -> String {
        var key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if key.hasSuffix(".app") { key.removeLast(4) }

        let words = key.split(separator: " ")
        if words.count > 1, let last = words.last, last.count == 4, last.allSatisfy(\.isNumber), last.hasPrefix("19") || last.hasPrefix("20") {
            key = words.dropLast().joined(separator: " ")
        }
        return key.trimmingCharacters(in: .whitespaces)
    }

    private static func looksLikeBundleId(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2
            && !value.lowercased().hasSuffix(".app")
            && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
    }
}
