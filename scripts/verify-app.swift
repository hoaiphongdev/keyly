import Cocoa

let repo = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let binary = repo.appendingPathComponent(".build/debug/Keyly")
let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/keyly")
let settingsFile = configDir.appendingPathComponent("setting.conf")
let sheetFile = configDir.appendingPathComponent("templates/zz-keyly-verify.keyly")
let fm = FileManager.default

guard AXIsProcessTrusted() else {
    print("✘ This terminal needs Accessibility permission to send key events")
    exit(2)
}
guard fm.fileExists(atPath: binary.path) else {
    print("✘ Run swift build first")
    exit(2)
}

func backup(_ url: URL) -> Data? { try? Data(contentsOf: url) }
let savedSettings = backup(settingsFile)
let hadSettings = (try? fm.attributesOfItem(atPath: settingsFile.path)) != nil
let savedSheet = backup(sheetFile)

func restore() {
    try? fm.removeItem(at: settingsFile)
    if hadSettings, let savedSettings { try? savedSettings.write(to: settingsFile) }
    try? fm.removeItem(at: sheetFile)
    if let savedSheet { try? savedSheet.write(to: sheetFile) }
}

final class Output {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ text: String) { lock.lock(); lines += text.split(separator: "\n").map(String.init); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return lines.count }
    func lines(from start: Int) -> [String] { lock.lock(); defer { lock.unlock() }; return Array(lines[min(start, lines.count)...]) }
}

let output = Output()
let logStream = Process()
logStream.executableURL = URL(fileURLWithPath: "/usr/bin/log")
logStream.arguments = ["stream", "--level", "info", "--style", "compact", "--predicate", "subsystem == \"com.keyly\""]
let logPipe = Pipe()
logStream.standardOutput = logPipe
logPipe.fileHandleForReading.readabilityHandler = { handle in
    if let text = String(data: handle.availableData, encoding: .utf8), !text.isEmpty { output.append(text) }
}

let process = Process()
process.executableURL = binary
process.environment = ProcessInfo.processInfo.environment.merging(["KEYLY_DEV": "1"]) { _, new in new }
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice

var failures = 0
func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    print(ok ? "✔ \(name)" : "✘ \(name) \(detail())")
    if !ok { failures += 1 }
}

func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

func waitFor(_ text: String, after start: Int, timeout: Double = 3) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if output.lines(from: start).contains(where: { $0.contains(text) }) { return true }
        pause(0.05)
    }
    return false
}

func writeSettings(_ text: String, expectTrigger label: String) -> Bool {
    let start = output.count
    try? text.write(to: settingsFile, atomically: true, encoding: .utf8)
    return waitFor("trigger \(label) in", after: start)
}

var pid: pid_t = 0
let source = CGEventSource(stateID: .privateState)

func post(_ event: CGEvent?) {
    event?.postToPid(pid)
    pause(0.04)
}

func flags(_ keyCode: CGKeyCode, _ flags: CGEventFlags) {
    let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
    event?.type = .flagsChanged
    event?.flags = flags
    post(event)
}

func key(_ keyCode: CGKeyCode, _ flags: CGEventFlags = [], down: Bool, repeat isRepeat: Bool = false) {
    let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
    event?.flags = flags
    if isRepeat { event?.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    post(event)
}

func tap(_ keyCode: CGKeyCode, _ flags: CGEventFlags = []) {
    key(keyCode, flags, down: true)
    key(keyCode, flags, down: false)
}

func overlayVisible() -> Bool {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { window in
        guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
        return (bounds["Height"] ?? 0) > 100
    }
}

func waitOverlay(_ expected: Bool, timeout: Double = 1.2) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if overlayVisible() == expected { return true }
        pause(0.05)
    } while Date() < deadline
    return overlayVisible() == expected
}

func closeOverlay() {
    if overlayVisible() { tap(53) }
    _ = waitOverlay(false)
    pause(0.6)
}

func scenario(_ name: String, opens expected: Bool, settle: Double = 0.4, _ steps: () -> Void) {
    closeOverlay()
    steps()
    pause(settle)
    let visible = waitOverlay(expected, timeout: expected ? 1.2 : 0.3) && overlayVisible() == expected
    check(visible, name, "(overlay \(overlayVisible() ? "opened" : "stayed closed"))")
}

let cmd: CGKeyCode = 55, shift: CGKeyCode = 56, ctrl: CGKeyCode = 59, fn: CGKeyCode = 63, capsLock: CGKeyCode = 57
let kKey: CGKeyCode = 40, cKey: CGKeyCode = 8, left: CGKeyCode = 123

try? fm.createDirectory(at: configDir.appendingPathComponent("templates"), withIntermediateDirectories: true)
try? fm.removeItem(at: settingsFile)

do {
    try logStream.run()
    Thread.sleep(forTimeInterval: 1.5)
    try process.run()
} catch {
    print("✘ Couldn't launch Keyly: \(error)")
    logStream.terminate()
    restore()
    exit(2)
}
pid = process.processIdentifier

check(waitFor("trigger ⇪ in", after: 0, timeout: 8), "launches with the Caps Lock default")
let created = (try? String(contentsOf: settingsFile, encoding: .utf8)) ?? ""
check(created.contains("# super_key = capslock"), "creates a fully commented setting.conf")
pause(1)

scenario("⇪ ⇪ opens", opens: true) {
    flags(capsLock, .maskAlphaShift)
    flags(capsLock, [])
}

check(writeSettings("super_key = cmd\ntrigger_type = press", expectTrigger: "⌘"), "reloads super_key = cmd, press")
scenario("⌘ ⌘ opens", opens: true) {
    flags(cmd, .maskCommand); flags(cmd, [])
    flags(cmd, .maskCommand); flags(cmd, [])
}
scenario("⌘ then ⌘⇧ released to ⌘ does not open", opens: false) {
    flags(cmd, .maskCommand)
    flags(shift, [.maskCommand, .maskShift])
    flags(shift, .maskCommand)
    flags(cmd, [])
}
scenario("⌘C then ⌘ does not open", opens: false) {
    flags(cmd, .maskCommand)
    tap(cKey, .maskCommand)
    flags(cmd, [])
    flags(cmd, .maskCommand); flags(cmd, [])
}
scenario("typing a letter between ⌘ taps does not open", opens: false) {
    flags(cmd, .maskCommand); flags(cmd, [])
    tap(kKey)
    flags(cmd, .maskCommand); flags(cmd, [])
}

check(writeSettings("super_key = Command\ntrigger_type = Hold\nhold_duration = 300ms", expectTrigger: "⌘"), "reloads super_key = Command, Hold, 300ms")
scenario("holding ⌘ 0.3s opens", opens: true, settle: 0.6) {
    flags(cmd, .maskCommand)
    pause(0.5)
    flags(cmd, [])
}
scenario("releasing ⌘ before 0.3s does not open", opens: false, settle: 0.6) {
    flags(cmd, .maskCommand)
    pause(0.1)
    flags(cmd, [])
}
scenario("⌘C during the hold cancels it", opens: false, settle: 0.6) {
    flags(cmd, .maskCommand)
    tap(cKey, .maskCommand)
    pause(0.5)
    flags(cmd, [])
}

check(writeSettings("super_key = ctrl + k\ntrigger_type = press", expectTrigger: "⌃K"), "reloads super_key = ctrl + k")
scenario("⌃K ⌃K opens", opens: true) {
    flags(ctrl, .maskControl)
    tap(kKey, .maskControl); tap(kKey, .maskControl)
    flags(ctrl, [])
}
scenario("⌃⌘K ⌃⌘K does not open", opens: false) {
    flags(ctrl, [.maskControl, .maskCommand])
    tap(kKey, [.maskControl, .maskCommand]); tap(kKey, [.maskControl, .maskCommand])
    flags(ctrl, [])
}
scenario("key repeat of ⌃K counts once", opens: false) {
    flags(ctrl, .maskControl)
    key(kKey, .maskControl, down: true)
    key(kKey, .maskControl, down: true, repeat: true)
    key(kKey, .maskControl, down: true, repeat: true)
    key(kKey, .maskControl, down: false)
    flags(ctrl, [])
}
scenario("a missed keyUp does not block the next ⌃K ⌃K", opens: true) {
    flags(ctrl, .maskControl)
    key(kKey, .maskControl, down: true)
    pause(0.6)
    key(kKey, .maskControl, down: true)
    key(kKey, .maskControl, down: false)
    tap(kKey, .maskControl)
    flags(ctrl, [])
}

check(writeSettings("super_key = fn\ntrigger_type = press", expectTrigger: "fn"), "reloads super_key = fn")
scenario("fn fn opens right after an arrow key", opens: true) {
    tap(left, [.maskSecondaryFn, .maskNumericPad])
    flags(fn, .maskSecondaryFn); flags(fn, [])
    flags(fn, .maskSecondaryFn); flags(fn, [])
}

var start = output.count
try? Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 131) }).write(to: settingsFile)
check(waitFor("trigger ⇪ in", after: start), "binary garbage in setting.conf falls back to Caps Lock")
check(process.isRunning, "still running after garbage settings")

start = output.count
for value in ["1", "2", "3", "4"] {
    try? "super_key = ctrl+k\npress_count = \(value)".write(to: settingsFile, atomically: true, encoding: .utf8)
    pause(0.05)
}
check(waitFor("trigger ⌃K in", after: start), "rapid saves reload")
pause(0.8)
let pressLines = output.lines(from: start).filter { $0.contains("Loaded") }
check(pressLines.count == 1, "rapid saves reload once", "(\(pressLines.count) reloads)")
start = output.count
check(writeSettings("super_key = ctrl+k\ntrigger_type = press\npress_count = 4", expectTrigger: "⌃K"), "reloads press_count = 4")
scenario("press_count = 4 needs four ⌃K", opens: true) {
    flags(ctrl, .maskControl)
    for _ in 0..<4 { tap(kKey, .maskControl) }
    flags(ctrl, [])
}

start = output.count
try? "super_key = ctrl+k\nhold_duratoin = 1\npress_count = 2".write(to: settingsFile, atomically: true, encoding: .utf8)
check(waitFor("Did you mean hold_duration?", after: start), "typo is reported with a suggestion")

start = output.count
try? "# App: \(ProcessInfo.processInfo.environment["TERM_PROGRAM"] == "iTerm.app" ? "iTerm" : "Terminal")\n[Verify]\n\\#   Hash key\nlonely\n".write(to: sheetFile, atomically: true, encoding: .utf8)
check(waitFor("zz-keyly-verify.keyly line 4", after: start), "bad template line is reported with its line number")
check(process.isRunning, "still running at the end")

process.terminate()
process.waitUntilExit()
logStream.terminate()
restore()
print(failures == 0 ? "\nAll checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
