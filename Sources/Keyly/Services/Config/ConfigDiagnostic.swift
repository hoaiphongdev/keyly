import Foundation
import os

/// A problem found while reading a config file. Never fatal: the line or value is skipped
/// and the rest of the config keeps working.
struct ConfigDiagnostic: Equatable {
    var file: URL?
    let line: Int?
    let message: String

    init(file: URL? = nil, line: Int?, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }

    /// "figma.keyly line 12: …"
    var summary: String {
        let place = [file?.lastPathComponent, line.map { "line \($0)" }].compactMap { $0 }.joined(separator: " ")
        return place.isEmpty ? message : "\(place): \(message)"
    }
}

enum ConfigLog {
    static let logger = Logger(subsystem: "com.keyly", category: "config")
    private static let isDevMode = ProcessInfo.processInfo.environment["KEYLY_DEV"] == "1"

    static func report(_ diagnostics: [ConfigDiagnostic]) {
        for diagnostic in diagnostics {
            logger.error("\(diagnostic.summary, privacy: .public)")
            if isDevMode { print("[Keyly] Config: \(diagnostic.summary)") }
        }
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        if isDevMode { print("[Keyly] \(message)") }
    }
}

/// Turns raw file bytes into lines without ever failing.
enum ConfigText {
    /// Files above this size are skipped; no shortcut sheet comes close
    static let maxFileSize = 1_000_000

    /// Invalid UTF-8 becomes U+FFFD instead of dropping the file; a leading BOM is removed
    static func decode(_ data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text
    }

    /// LF, CRLF and CR all end a line, so line numbers match what editors show
    static func lines(_ text: String) -> [Substring] {
        let body = text.hasPrefix("\u{FEFF}") ? text.dropFirst() : Substring(text)
        return body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }

    enum ReadResult {
        case text(String)
        case missing
        case failed(ConfigDiagnostic)
    }

    static func read(_ url: URL) -> ReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxFileSize {
            return .failed(ConfigDiagnostic(file: url, line: nil, message: "File is larger than 1 MB, skipped"))
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failed(ConfigDiagnostic(file: url, line: nil, message: "Couldn't read the file"))
        }
        return .text(decode(data))
    }
}

extension String {
    /// Edit distance, used to suggest the closest name for a typo
    func distance(to other: String) -> Int {
        let a = Array(self), b = Array(other)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
