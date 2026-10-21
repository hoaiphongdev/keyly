import Foundation
import os

struct ConfigDiagnostic: Equatable {
    var file: URL?
    let line: Int?
    let message: String

    init(file: URL? = nil, line: Int?, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }

    var summary: String {
        let place = [file?.lastPathComponent, line.map { "line \($0)" }].compactMap { $0 }.joined(separator: " ")
        return place.isEmpty ? message : "\(place): \(message)"
    }
}

enum ConfigLog {
    static let logger = Logger(subsystem: "com.keyly", category: "config")
    private static let isDevMode = AppConstants.isDevMode

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

enum ConfigText {
    static let maxFileSize = 1_000_000

    static func decode(_ data: Data) -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func lines(_ text: String) -> [Substring] {
        let body = text.hasPrefix("\u{FEFF}") ? text.dropFirst() : Substring(text)
        return body.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
    }

    enum ReadResult {
        case text(String)
        case missing
        case failed(ConfigDiagnostic)
    }

    static func read(_ url: URL) -> ReadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }

        if let size = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxFileSize {
            return .failed(ConfigDiagnostic(file: url, line: nil, message: "File is larger than 1 MB, skipped"))
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failed(ConfigDiagnostic(file: url, line: nil, message: "Couldn't read the file"))
        }
        return .text(decode(data))
    }
}
