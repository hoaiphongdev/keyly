import Cocoa


var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
let isRelease = arguments.contains("--release")
let repo = URL(fileURLWithPath: option("--repo") ?? FileManager.default.currentDirectoryPath)
let binary = URL(fileURLWithPath: option("--binary") ?? repo.appendingPathComponent(".build/debug/Keyly").path)
let only = option("--only")
let defaultsDomain = isRelease ? "com.keyly.app" : "Keyly"

let fm = FileManager.default
let home = fm.homeDirectoryForCurrentUser
let configDir = home.appendingPathComponent(".config/keyly")
let templatesDir = configDir.appendingPathComponent("templates")
let settingsFile = configDir.appendingPathComponent("setting.conf")
let work = fm.temporaryDirectory.appendingPathComponent("keyly-verify-\(UUID().uuidString)")
let backupDir = work.appendingPathComponent("config-backup")
let fakeBin = work.appendingPathComponent("bin")
let codeArgsFile = work.appendingPathComponent("code-args")
let stderrFile = work.appendingPathComponent("keyly-stderr")
let stdoutFile = work.appendingPathComponent("keyly-stdout")
let sinkApp = work.appendingPathComponent("KeylyVerifySink 2025.app")

guard AXIsProcessTrusted() else {
    print("✘ This terminal needs Accessibility permission")
    exit(2)
}
if let session = CGSessionCopyCurrentDictionary() as? [String: Any], (session["CGSSessionScreenIsLocked"] as? Bool) == true {
    print("✘ The screen is locked; unlock it and keep hands off the keyboard while this runs")
    exit(2)
}
guard fm.fileExists(atPath: binary.path) else {
    print("✘ Missing \(binary.path)")
    exit(2)
}

func shell(_ command: String) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", command]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}


try? fm.createDirectory(at: work, withIntermediateDirectories: true)
let hadConfig = (try? fm.attributesOfItem(atPath: configDir.path)) != nil
if hadConfig { try! fm.moveItem(at: configDir, to: backupDir) }
let defaultsBackup = work.appendingPathComponent("defaults.plist")
let hadDefaults = shell("defaults export \(defaultsDomain) '\(defaultsBackup.path)'").status == 0
let capsLockWasOn = CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
let textEditWasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").isEmpty
print("Config backed up to \(backupDir.path)")

var restored = false
func restoreEverything() {
    guard !restored else { return }
    restored = true
    try? fm.removeItem(at: configDir)
    if hadConfig { try? fm.moveItem(at: backupDir, to: configDir) }
    _ = shell("defaults delete \(defaultsDomain) 2>/dev/null")
    if hadDefaults { _ = shell("defaults import \(defaultsDomain) '\(defaultsBackup.path)'") }
}
signal(SIGINT) { _ in restoreEverything(); exit(130) }
signal(SIGTERM) { _ in restoreEverything(); exit(143) }

func freshConfig() {
    try? fm.removeItem(at: configDir)
    try? fm.createDirectory(at: templatesDir, withIntermediateDirectories: true)
}


func buildSink() -> Bool {
    let macOS = sinkApp.appendingPathComponent("Contents/MacOS")
    try? fm.createDirectory(at: macOS, withIntermediateDirectories: true)
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>com.keyly.VerifySink</string>
    <key>CFBundleName</key><string>KeylyVerifySink</string>
    <key>CFBundleExecutable</key><string>KeylyVerifySink</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    </dict></plist>
    """
    try? plist.write(to: sinkApp.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
    let source = repo.appendingPathComponent("scripts/verify/Sink.swift").path
    return shell("swiftc -O '\(source)' -o '\(macOS.appendingPathComponent("KeylyVerifySink").path)'").status == 0
}

try? fm.createDirectory(at: fakeBin, withIntermediateDirectories: true)
try? "#!/bin/bash\nprintf '%s\\n' \"$@\" > '\(codeArgsFile.path)'\n".write(to: fakeBin.appendingPathComponent("code"), atomically: true, encoding: .utf8)
_ = shell("chmod +x '\(fakeBin.appendingPathComponent("code").path)'")


final class Lines {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ text: String) { lock.lock(); lines += text.split(separator: "\n").map(String.init); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return lines.count }
    func since(_ start: Int) -> [String] { lock.lock(); defer { lock.unlock() }; return Array(lines[min(start, lines.count)...]) }
}
let log = Lines()
let logStream = Process()
logStream.executableURL = URL(fileURLWithPath: "/usr/bin/log")
logStream.arguments = ["stream", "--level", "info", "--style", "compact", "--predicate", "subsystem == \"com.keyly\""]
let logPipe = Pipe()
logStream.standardOutput = logPipe
logPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if !data.isEmpty { log.append(String(decoding: data, as: UTF8.self)) }
}
try! logStream.run()
Thread.sleep(forTimeInterval: 1.5)

func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

func eventually(_ timeout: Double = 4, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return true }
        pause(0.1)
    } while Date() < deadline
    return condition()
}

func waitLog(_ text: String, after start: Int, timeout: Double = 4) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if log.since(start).contains(where: { $0.contains(text) }) { return true }
        pause(0.05)
    }
    return false
}


var failures: [String] = []
var passes = 0
func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if ok {
        passes += 1
        print("✔ \(name)")
    } else {
        let line = "\(name) \(detail())"
        failures.append(line)
        print("✘ \(line)")
    }
}
func group(_ name: String) -> Bool {
    let run = (only == nil || only == name) && !arguments.contains("--skip-\(name)")
    if run { print("\n— \(name)") }
    return run
}


var keyly: Process?
var pid: pid_t = 0

func launchKeyly() -> Bool {
    let process = Process()
    process.executableURL = binary
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "\(fakeBin.path):" + (environment["PATH"] ?? "/usr/bin:/bin")
    if isRelease { environment.removeValue(forKey: "KEYLY_DEV") } else { environment["KEYLY_DEV"] = "1" }
    process.environment = environment
    if !fm.fileExists(atPath: stderrFile.path) { fm.createFile(atPath: stderrFile.path, contents: nil) }
    let stderrHandle = try? FileHandle(forWritingTo: stderrFile)
    stderrHandle?.seekToEndOfFile()
    if !fm.fileExists(atPath: stdoutFile.path) { fm.createFile(atPath: stdoutFile.path, contents: nil) }
    let stdoutHandle = try? FileHandle(forWritingTo: stdoutFile)
    stdoutHandle?.seekToEndOfFile()
    process.standardOutput = stdoutHandle ?? FileHandle.nullDevice
    process.standardError = stderrHandle ?? FileHandle.nullDevice
    let start = log.count
    do { try process.run() } catch { return false }
    keyly = process
    pid = process.processIdentifier
    let loaded = waitLog("Loaded ", after: start, timeout: 10)
    pause(1)
    return loaded
}

func quitKeyly() {
    keyly?.terminate()
    keyly?.waitUntilExit()
    keyly = nil
}


var sink: NSRunningApplication?
func launchSink() -> Bool {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: sinkApp, configuration: configuration) { app, _ in
        sink = app
        done.signal()
    }
    done.wait()
    pause(1)
    return sink != nil
}

@discardableResult
func focusSink() -> Bool {
    func isFront() -> Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == sink?.processIdentifier }
    if isFront() { return true }
    sink?.activate(options: [])
    for attempt in 0..<40 {
        if isFront() { return true }
        if attempt == 10 { _ = shell("open -a '\(sinkApp.path)'") }
        pause(0.05)
    }
    return isFront()
}


let harnessMark: Int64 = 0x4B45594C59
final class Interference {
    private let lock = NSLock()
    private var flag = false
    func mark() { lock.lock(); flag = true; lock.unlock() }
    func take() -> Bool { lock.lock(); defer { flag = false; lock.unlock() }; return flag }
}
let interference = Interference()

func watchForUserInput() {
    let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    let thread = Thread {
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: mask, callback: { _, _, event, _ in
            if event.getIntegerValueField(.eventSourceUserData) != harnessMark { interference.mark() }
            return Unmanaged.passUnretained(event)
        }, userInfo: nil) else { return }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        CFRunLoopRun()
    }
    thread.start()
}
watchForUserInput()

enum Route { case pid, hid }
var route = Route.pid
let pidSource = CGEventSource(stateID: .privateState)
let hidSource = CGEventSource(stateID: .hidSystemState)

var lostFocus = false
func post(_ event: CGEvent?) {
    event?.setIntegerValueField(.eventSourceUserData, value: harnessMark)
    switch route {
    case .pid:
        event?.postToPid(pid)
    case .hid:
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == sink?.processIdentifier else {
            lostFocus = true
            return
        }
        event?.post(tap: .cghidEventTap)
    }
    pause(0.04)
}
func source() -> CGEventSource? { route == .pid ? pidSource : hidSource }

func flags(_ keyCode: CGKeyCode, _ flags: CGEventFlags) {
    let event = CGEvent(keyboardEventSource: source(), virtualKey: keyCode, keyDown: true)
    event?.type = .flagsChanged
    event?.flags = flags
    post(event)
}
func key(_ keyCode: CGKeyCode, _ flags: CGEventFlags = [], down: Bool, repeat isRepeat: Bool = false) {
    let event = CGEvent(keyboardEventSource: source(), virtualKey: keyCode, keyDown: down)
    event?.flags = flags
    if isRepeat { event?.setIntegerValueField(.keyboardEventAutorepeat, value: 1) }
    post(event)
}
func tap(_ keyCode: CGKeyCode, _ flags: CGEventFlags = []) {
    key(keyCode, flags, down: true)
    key(keyCode, flags, down: false)
}
func releaseAllModifiers() {
    for code: CGKeyCode in [55, 56, 58, 59, 63] { flags(code, []) }
}

let cmd: CGKeyCode = 55, shift: CGKeyCode = 56, ctrl: CGKeyCode = 59, fn: CGKeyCode = 63, capsLock: CGKeyCode = 57
let kKey: CGKeyCode = 40, cKey: CGKeyCode = 8, left: CGKeyCode = 123, escape: CGKeyCode = 53

func capsTwice() {
    let saved = route
    route = .pid
    flags(capsLock, .maskAlphaShift)
    flags(capsLock, [])
    route = saved
}


func overlayVisible() -> Bool {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { window in
        guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
        return (bounds["Height"] ?? 0) > 100
    }
}

func waitOverlay(_ expected: Bool, timeout: Double) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if overlayVisible() == expected { return true }
        pause(0.005)
    } while Date() < deadline
    return overlayVisible() == expected
}

func closeOverlay() {
    let saved = route
    route = .pid
    for _ in 0..<3 where overlayVisible() {
        tap(escape)
        _ = waitOverlay(false, timeout: 0.5)
    }
    route = saved
    pause(0.6)
}

func scenario(_ name: String, opens expected: Bool, settle: Double = 0.4, _ steps: () -> Void) {
    var lastDetail = ""
    for attempt in 1...4 {
        closeOverlay()
        guard focusSink() else {
            lastDetail = "(sink app couldn't be brought to the front)"
            pause(1)
            continue
        }
        let outputStart = (try? String(contentsOf: stdoutFile, encoding: .utf8))?.count ?? 0
        _ = interference.take()
        lostFocus = false
        steps()
        releaseAllModifiers()
        pause(settle)
        let ok = waitOverlay(expected, timeout: expected ? 1.2 : 0.3) && overlayVisible() == expected
        if interference.take() || lostFocus {
            lastDetail = "(interrupted by user input or focus change, attempt \(attempt))"
            print("  ↻ \(name): retrying, \(lostFocus ? "focus left the sink app" : "user input detected")")
            pause(1.5)
            continue
        }
        check(ok, name, "(overlay \(overlayVisible() ? "opened" : "stayed closed"))")
        if !ok, let output = try? String(contentsOf: stdoutFile, encoding: .utf8) {
            print(output.dropFirst(outputStart).split(separator: "\n").filter { !$0.contains("Flags changed") }.suffix(25).map { "    | \($0)" }.joined(separator: "\n"))
        }
        return
    }
    check(false, name, lastDetail)
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}
func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}
func texts(of element: AXUIElement) -> [String] {
    [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].compactMap { attribute(element, $0) as? String }.filter { !$0.isEmpty }
}
func walk(_ element: AXUIElement, depth: Int = 0, _ visit: (AXUIElement) -> Void) {
    visit(element)
    guard depth < 40 else { return }
    for child in children(element) { walk(child, depth: depth + 1, visit) }
}
var keylyAX: AXUIElement { AXUIElementCreateApplication(pid) }

func overlayTexts() -> [String] {
    var result: [String] = []
    for window in (attribute(keylyAX, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
        walk(window) { result += texts(of: $0) }
    }
    return result
}

func openOverlayTexts() -> [String] {
    var texts: [String] = []
    for _ in 1...4 {
        closeOverlay()
        guard focusSink() else { pause(1); continue }
        _ = interference.take()
        capsTwice()
        _ = waitOverlay(true, timeout: 1.5)
        _ = eventually(3) {
            texts = overlayTexts()
            return texts.contains { $0.contains(", ") }
        }
        if !interference.take() && texts.first == "KeylyVerifySink" { return texts }
        print("  ↻ overlay read interrupted, retrying")
        pause(1.5)
    }
    return texts
}

func press(_ element: AXUIElement) {
    DispatchQueue.global().async { AXUIElementPerformAction(element, kAXPressAction as CFString) }
    pause(0.8)
}

func menuItems() -> [AXUIElement] {
    var items: [AXUIElement] = []
    walk(keylyAX) { element in
        if (attribute(element, kAXRoleAttribute) as? String) == "AXMenuItem" { items.append(element) }
    }
    return items
}

func openGearMenu() -> Bool {
    var gear: AXUIElement?
    for window in (attribute(keylyAX, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
        walk(window) { element in
            if (attribute(element, kAXRoleAttribute) as? String) == "AXButton",
               (attribute(element, kAXDescriptionAttribute) as? String) == "Settings" { gear = element }
        }
    }
    guard let gear else { return false }
    press(gear)
    return true
}

func titled(_ prefix: String) -> AXUIElement? {
    menuItems().first { (attribute($0, kAXTitleAttribute) as? String)?.hasPrefix(prefix) == true }
}

func dismissMenus() {
    let saved = route
    route = .hid
    tap(escape)
    pause(0.3)
    route = saved
}


func write(_ text: String, to url: URL) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? text.write(to: url, atomically: true, encoding: .utf8)
}

func writeAndReload(_ text: String, to url: URL, expect: String = "Loaded ") -> Bool {
    let start = log.count
    write(text, to: url)
    let ok = waitLog(expect, after: start)
    pause(0.8)
    return ok
}

func setSettings(_ text: String, trigger label: String) -> Bool {
    writeAndReload(text, to: settingsFile, expect: "trigger \(label) in")
}

func lastReloadMilliseconds(after start: Int) -> Int? {
    guard let line = log.since(start).last(where: { $0.contains("Loaded ") }),
          let range = line.range(of: #"in (\d+) ms"#, options: .regularExpression) else { return nil }
    return Int(line[range].dropFirst(3).dropLast(3))
}


guard buildSink(), launchSink() else {
    print("✘ Couldn't build or launch the sink app")
    restoreEverything()
    exit(2)
}

freshConfig()
check(launchKeyly(), "launches and loads its config")
check((try? String(contentsOf: settingsFile, encoding: .utf8))?.contains("# super_key = capslock") == true, "creates a fully commented setting.conf")
if isRelease {
    check(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.keyly.app", "release bundle id is com.keyly.app")
}

if group("trigger-pid") {
    route = .pid
    scenario("pid: ⇪ ⇪ opens", opens: true) { flags(capsLock, .maskAlphaShift); flags(capsLock, []) }
    check(setSettings("super_key = cmd\ntrigger_type = press", trigger: "⌘"), "pid: reloads super_key = cmd")
    scenario("pid: ⌘ ⌘ opens", opens: true) { flags(cmd, .maskCommand); flags(cmd, []); flags(cmd, .maskCommand); flags(cmd, []) }
    scenario("pid: ⌘ then ⌘⇧ released does not open", opens: false) {
        flags(cmd, .maskCommand); flags(shift, [.maskCommand, .maskShift]); flags(shift, .maskCommand); flags(cmd, [])
    }
    scenario("pid: ⌘C then ⌘ does not open", opens: false) {
        flags(cmd, .maskCommand); tap(cKey, .maskCommand); flags(cmd, []); flags(cmd, .maskCommand); flags(cmd, [])
    }
    check(setSettings("super_key = ctrl+k\ntrigger_type = press", trigger: "⌃K"), "pid: reloads super_key = ctrl+k")
    scenario("pid: a missed keyUp does not block ⌃K ⌃K", opens: true) {
        flags(ctrl, .maskControl); key(kKey, .maskControl, down: true); pause(0.6)
        key(kKey, .maskControl, down: true); key(kKey, .maskControl, down: false); tap(kKey, .maskControl); flags(ctrl, [])
    }
    check(setSettings("super_key = fn\ntrigger_type = press", trigger: "fn"), "pid: reloads super_key = fn")
    scenario("pid: fn fn opens right after an arrow key", opens: true) {
        tap(left, [.maskSecondaryFn, .maskNumericPad])
        flags(fn, .maskSecondaryFn); flags(fn, []); flags(fn, .maskSecondaryFn); flags(fn, [])
    }
    check(setSettings("super_key = fn+f1", trigger: "⇪"), "pid: fn+f1 is rejected, Caps Lock is used")
}

if group("trigger-hid") {
    route = .hid
    check(setSettings("super_key = capslock", trigger: "⇪"), "hid: reloads super_key = capslock")
    scenario("hid: ⇪ ⇪ opens", opens: true) { flags(capsLock, .maskAlphaShift); flags(capsLock, []) }
    check(setSettings("super_key = cmd\ntrigger_type = press", trigger: "⌘"), "hid: reloads super_key = cmd, press")
    scenario("hid: ⌘ ⌘ opens", opens: true) { flags(cmd, .maskCommand); flags(cmd, []); flags(cmd, .maskCommand); flags(cmd, []) }
    scenario("hid: ⌘ then ⌘⇧ released does not open", opens: false) {
        flags(cmd, .maskCommand); flags(shift, [.maskCommand, .maskShift]); flags(shift, .maskCommand); flags(cmd, [])
    }
    scenario("hid: ⌘C then ⌘ does not open", opens: false) {
        flags(cmd, .maskCommand); tap(cKey, .maskCommand); flags(cmd, []); flags(cmd, .maskCommand); flags(cmd, [])
    }
    scenario("hid: typing a letter between ⌘ taps does not open", opens: false) {
        flags(cmd, .maskCommand); flags(cmd, []); tap(kKey); flags(cmd, .maskCommand); flags(cmd, [])
    }
    check(setSettings("super_key = cmd\ntrigger_type = press\npress_count = 1", trigger: "⌘"), "hid: reloads press_count = 1")
    scenario("hid: ⌘C with press_count = 1 does not open", opens: false) { flags(cmd, .maskCommand); tap(cKey, .maskCommand); flags(cmd, []) }
    scenario("hid: one ⌘ tap with press_count = 1 opens", opens: true) { flags(cmd, .maskCommand); flags(cmd, []) }
    check(setSettings("super_key = Command\ntrigger_type = Hold\nhold_duration = 300ms", trigger: "⌘"), "hid: reloads Command, Hold, 300ms")
    scenario("hid: holding ⌘ 0.3s opens", opens: true, settle: 0.6) { flags(cmd, .maskCommand); pause(0.5); flags(cmd, []) }
    scenario("hid: releasing ⌘ early does not open", opens: false, settle: 0.6) { flags(cmd, .maskCommand); pause(0.1); flags(cmd, []) }
    scenario("hid: ⌘C during the hold cancels it", opens: false, settle: 0.6) { flags(cmd, .maskCommand); tap(cKey, .maskCommand); pause(0.5); flags(cmd, []) }
    check(setSettings("super_key = ctrl + k\ntrigger_type = press", trigger: "⌃K"), "hid: reloads ctrl + k")
    scenario("hid: ⌃K ⌃K opens", opens: true) { flags(ctrl, .maskControl); tap(kKey, .maskControl); tap(kKey, .maskControl); flags(ctrl, []) }
    scenario("hid: ⌃⌘K ⌃⌘K does not open", opens: false) {
        flags(ctrl, [.maskControl, .maskCommand]); tap(kKey, [.maskControl, .maskCommand]); tap(kKey, [.maskControl, .maskCommand]); flags(ctrl, [])
    }
    scenario("hid: key repeat of ⌃K counts once", opens: false) {
        flags(ctrl, .maskControl); key(kKey, .maskControl, down: true)
        key(kKey, .maskControl, down: true, repeat: true); key(kKey, .maskControl, down: true, repeat: true)
        key(kKey, .maskControl, down: false); flags(ctrl, [])
    }
    closeOverlay()
    focusSink()
    flags(ctrl, .maskControl); tap(kKey, .maskControl); tap(kKey, .maskControl); flags(ctrl, [])
    _ = waitOverlay(true, timeout: 1.2)
    tap(escape)
    check(waitOverlay(false, timeout: 1), "hid: ESC closes the overlay")
    route = .pid
}

if group("matching") {
    _ = setSettings("super_key = capslock", trigger: "⇪")
    let sheet = templatesDir.appendingPathComponent("sink.keyly")
    func shows(_ app: String, _ label: String) -> Bool {
        _ = writeAndReload("# App: \(app)\n[Verify]\nX  \(label)", to: sheet)
        return openOverlayTexts().contains { $0.hasPrefix(label + ",") }
    }
    check(shows("KeylyVerifySink", "By name"), "matches # App: by app name")
    check(shows("COM.KEYLY.verifysink", "By bundle id"), "matches # App: by bundle id, any case")
    check(shows("/Applications/KeylyVerifySink 2024.app", "By old year path"), "matches a missing path by name without the year")
    check(shows("/Applications/Nope.app", "Wrong app") == false, "does not match another app")
    _ = writeAndReload("# App: KeylyVerifySink\n## App: com.other.app\n[Verify]\nX  Double hash ignored", to: sheet)
    check(openOverlayTexts().contains("Double hash ignored, X"), "## App: is a comment")
    try? fm.removeItem(at: sheet)
    closeOverlay()
}

if group("content") {
    _ = setSettings("super_key = capslock", trigger: "⇪")
    let sheet = templatesDir.appendingPathComponent("sink.keyly")
    _ = writeAndReload("""
    # App: KeylyVerifySink
    [Verify]
    \\#          Hash key
    CMD+SHIFT+T Reopen
    ⌘+click     Add cursor
    CMD+Comma   Settings
    """, to: sheet)
    var items = openOverlayTexts()
    check(items.contains("Hash key, #"), "\\# shows the # key", "\(items)")
    check(items.contains("Reopen, ⇧⌘T"), "CMD+SHIFT+T shows ⇧⌘T")
    check(items.contains("Add cursor, ⌘+click"), "⌘+click keeps its +")
    check(items.contains("Settings, ⌘Comma"), "CMD+Comma shows ⌘Comma")
    check(items.contains("Sink Action, ⌘J"), "menu shortcuts still show next to the sheet")

    _ = writeAndReload("# App: KeylyVerifySink\n# Hide Default: true\n[Verify]\nX  Only mine", to: sheet)
    items = openOverlayTexts()
    check(items.contains("Only mine, X") && !items.contains("Sink Action, ⌘J"), "Hide Default hides menu shortcuts")

    _ = writeAndReload("# App: KeylyVerifySink\n[Verify]\nX  Live one", to: sheet)
    _ = openOverlayTexts()
    let start = log.count
    write("# App: KeylyVerifySink\n[Verify]\nX  Live one\nY  Live two", to: sheet)
    _ = waitLog("Loaded ", after: start)
    pause(0.8)
    check(eventually { overlayVisible() && overlayTexts().contains("Live two, Y") }, "an open overlay updates when a sheet is saved")
    closeOverlay()

    func searchText() -> String? {
        var value: String?
        for window in (attribute(keylyAX, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            walk(window) { element in
                if ["AXTextField", "AXSearchField"].contains(attribute(element, kAXRoleAttribute) as? String ?? "") {
                    value = attribute(element, kAXValueAttribute) as? String
                }
            }
        }
        return value
    }
    var searchKept = false
    for _ in 1...3 where !searchKept {
        _ = openOverlayTexts()
        route = .hid
        _ = interference.take()
        for code: CGKeyCode in [1, 34, 45] { tap(code) }
        route = .pid
        let typed = eventually(2) { searchText() == "sin" }
        let unrelated = log.count
        try? Data([1, 2, 3]).write(to: configDir.appendingPathComponent(".DS_Store"))
        _ = waitLog("Loaded ", after: unrelated, timeout: 2)
        pause(1)
        if interference.take() || lostFocus { print("  ↻ search check interrupted, retrying"); continue }
        searchKept = typed && overlayVisible() && searchText() == "sin"
        break
    }
    check(searchKept, "saving an unrelated file keeps the open overlay and its search")
    try? fm.removeItem(at: configDir.appendingPathComponent(".DS_Store"))
    closeOverlay()

    let global = templatesDir.appendingPathComponent("global.keyly")
    _ = writeAndReload("[Edit]\n> Universal editing\nCMD+Z  Global undo", to: global)
    items = openOverlayTexts()
    check(items.contains("Global undo, ⌘Z"), "global.keyly shows in every app")
    check(!items.contains { $0.contains("Universal editing") }, "global descriptions don't label the app's menu categories")
    try? fm.removeItem(at: global)

    let older = configDir.appendingPathComponent("dup.keyly")
    _ = writeAndReload("# App: KeylyVerifySink\n[Verify]\nX  Old copy", to: older)
    let touched = log.count
    try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: older.path)
    _ = waitLog("Loaded ", after: touched, timeout: 2)
    pause(0.8)
    _ = writeAndReload("# App: KeylyVerifySink\n[Verify]\nX  New copy", to: templatesDir.appendingPathComponent("dup.keyly"))
    items = openOverlayTexts()
    check(items.contains("New copy, X") && !items.contains("Old copy, X"), "the copy saved last wins")

    _ = shell("chmod 000 '\(sheet.path)'")
    let unreadable = log.count
    _ = shell("touch '\(templatesDir.appendingPathComponent("dup.keyly").path)'")
    _ = waitLog("Loaded ", after: unreadable)
    pause(0.8)
    items = openOverlayTexts()
    check(items.contains("Live one, X"), "a file that can't be read keeps its last good version")
    check(log.since(unreadable).contains { $0.contains("Couldn't read the file") }, "an unreadable file is reported")
    _ = shell("chmod 644 '\(sheet.path)'")
    try? fm.removeItem(at: older)
    try? fm.removeItem(at: templatesDir.appendingPathComponent("dup.keyly"))
    try? fm.removeItem(at: sheet)
    closeOverlay()
}

if group("menu") {
    _ = setSettings("super_key = capslock", trigger: "⇪")
    _ = shell("defaults delete \(defaultsDomain) KeylyPreferredEditor 2>/dev/null")
    let bad = templatesDir.appendingPathComponent("bad.keyly")
    _ = writeAndReload("# App: KeylyVerifySink\n[Verify]\nX  Fine\nlonely\n", to: bad)
    _ = writeAndReload("super_key = capslock\nhold_duratoin = 1", to: settingsFile)

    _ = openOverlayTexts()
    check(openGearMenu(), "opens the ⚙︎ menu")
    let problems = titled("⚠︎")
    check((problems.flatMap { attribute($0, kAXTitleAttribute) as? String }) == "⚠︎ 2 config problems", "⚙︎ menu counts the problems",
          "(\(problems.flatMap { attribute($0, kAXTitleAttribute) as? String } ?? "none"))")
    let entries = problems.map { children($0).flatMap(children).compactMap { attribute($0, kAXTitleAttribute) as? String } } ?? []
    check(entries.contains("bad.keyly line 4: Couldn't tell the shortcut from its description. Put two spaces or | between them"), "lists the template problem with its line", "\(entries)")
    check(entries.contains { $0.hasPrefix("setting.conf line 2: Unknown setting \"hold_duratoin\". Did you mean hold_duration?") }, "lists the settings typo with a suggestion")

    try? fm.removeItem(at: codeArgsFile)
    if let item = problems.flatMap({ children($0).flatMap(children).first { (attribute($0, kAXTitleAttribute) as? String)?.hasPrefix("bad.keyly") == true } }) {
        press(item)
        pause(0.5)
        var picker: AXUIElement?
        for window in (attribute(keylyAX, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            walk(window) { element in
                if (attribute(element, kAXRoleAttribute) as? String) == "AXButton", (attribute(element, kAXTitleAttribute) as? String) == "VS Code" { picker = element }
            }
        }
        check(picker != nil, "asks which editor to use the first time")
        if let picker { press(picker) }
        pause(1)
        let args = (try? String(contentsOf: codeArgsFile, encoding: .utf8)) ?? ""
        check(args == "--goto\n\(bad.path):4\n", "opens VS Code at the problem line", "(\(args.debugDescription))")
        check(shell("defaults read \(defaultsDomain) KeylyPreferredEditor").output.contains("vscode"), "remembers the editor choice")
    } else {
        check(false, "finds the problem item to click")
    }

    _ = shell("defaults write \(defaultsDomain) KeylyPreferredEditor textedit")
    pause(0.5)
    _ = openOverlayTexts()
    _ = openGearMenu()
    if let item = titled("⚠︎").flatMap({ children($0).flatMap(children).first { (attribute($0, kAXTitleAttribute) as? String)?.hasPrefix("bad.keyly") == true } }) {
        press(item)
        var opened = false
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline && !opened {
            if let textEdit = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first {
                let ax = AXUIElementCreateApplication(textEdit.processIdentifier)
                for window in (attribute(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] where (attribute(window, kAXTitleAttribute) as? String)?.contains("bad.keyly") == true {
                    opened = true
                    if let close = attribute(window, kAXCloseButtonAttribute) {
                        AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString)
                    }
                }
            }
            pause(0.2)
        }
        check(opened, "opens the file in TextEdit")
        if !textEditWasRunning {
            pause(0.5)
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").forEach { $0.terminate() }
        }
    } else {
        check(false, "finds the problem item for TextEdit")
    }

    _ = shell("defaults write \(defaultsDomain) KeylyPreferredEditor vscode")
    pause(0.5)
    write("# keep", to: templatesDir.appendingPathComponent("example.keyly"))
    try? fm.removeItem(at: codeArgsFile)
    _ = openOverlayTexts()
    _ = openGearMenu()
    if let folderItem = titled("Open Config Folder") {
        press(folderItem)
        pause(1)
        let args = (try? String(contentsOf: codeArgsFile, encoding: .utf8)) ?? ""
        check(args == configDir.path + "/\n" || args == configDir.path + "\n", "Open Config Folder opens the folder in the editor", "(\(args.debugDescription))")
        check((try? String(contentsOf: templatesDir.appendingPathComponent("example.keyly"), encoding: .utf8)) == "# keep", "Open Config Folder keeps an existing example.keyly")
        check(fm.fileExists(atPath: templatesDir.appendingPathComponent("global.keyly").path), "Open Config Folder adds a missing global.keyly")
    } else {
        check(false, "finds Open Config Folder")
    }
    dismissMenus()
    for name in ["bad.keyly", "example.keyly", "global.keyly"] { try? fm.removeItem(at: templatesDir.appendingPathComponent(name)) }
    _ = writeAndReload("super_key = capslock", to: settingsFile)
    closeOverlay()
}

if group("robustness") {
    var start = log.count
    try? Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 131) }).write(to: settingsFile)
    check(waitLog("trigger ⇪ in", after: start), "binary garbage in setting.conf falls back to Caps Lock")
    pause(0.8)

    let big = work.appendingPathComponent("big.keyly")
    try? Data(count: 1_200_000).write(to: big)
    start = log.count
    try? Data(count: 1_200_000).write(to: templatesDir.appendingPathComponent("huge.keyly"))
    check(waitLog("huge.keyly: File is larger than 1 MB", after: start), "a file over 1 MB is skipped and reported")
    pause(0.8)
    start = log.count
    try? fm.createSymbolicLink(at: templatesDir.appendingPathComponent("linked.keyly"), withDestinationURL: big)
    check(waitLog("linked.keyly: File is larger than 1 MB", after: start), "a symlink to a file over 1 MB is skipped too")
    try? fm.removeItem(at: templatesDir.appendingPathComponent("huge.keyly"))
    try? fm.removeItem(at: templatesDir.appendingPathComponent("linked.keyly"))
    pause(0.8)

    start = log.count
    for value in ["cmd", "alt", "shift", "ctrl+k"] {
        write("super_key = \(value)", to: settingsFile)
        pause(0.05)
    }
    _ = waitLog("trigger ⌃K in", after: start)
    pause(1.2)
    check(log.since(start).last { $0.contains("Loaded ") }?.contains("trigger ⌃K in") == true, "rapid saves end on the last save")
    check(keyly?.isRunning == true, "still running after the robustness checks")
    _ = writeAndReload("super_key = capslock", to: settingsFile)
}

if group("performance") {
    let start = log.count
    for file in (try? fm.contentsOfDirectory(at: repo.appendingPathComponent("templates"), includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "keyly" {
        try? fm.copyItem(at: file, to: templatesDir.appendingPathComponent(file.lastPathComponent))
    }
    _ = waitLog("Loaded 31 sheet(s)", after: start, timeout: 6)
    pause(1)
    let reload = log.count
    _ = shell("touch '\(templatesDir.appendingPathComponent("figma.keyly").path)'")
    _ = waitLog("Loaded ", after: reload)
    let ms = lastReloadMilliseconds(after: reload) ?? 9999
    let budget = isRelease ? 50 : 100
    check(ms < budget, "reloading 31 templates takes under \(budget) ms", "(\(ms) ms)")
    print("  reload: \(ms) ms")
    pause(0.8)

    var latencies: [Double] = []
    for _ in 0..<5 {
        closeOverlay()
        let begin = Date()
        capsTwice()
        _ = waitOverlay(true, timeout: 1)
        latencies.append(Date().timeIntervalSince(begin) * 1000)
    }
    let worst = latencies.max() ?? 9999
    check(worst < 250, "trigger to overlay under 250 ms", "(worst \(Int(worst)) ms)")
    print("  trigger to overlay: \(latencies.map { "\(Int($0))" }.joined(separator: ", ")) ms")

    closeOverlay()
    let line = "CMD+SHIFT+K        Something long enough to make the file big\n"
    write("# App: KeylyVerifySink\n[Big]\n" + String(repeating: line, count: 15_000), to: templatesDir.appendingPathComponent("big.keyly"))
    pause(0.35)
    let begin = Date()
    capsTwice()
    let opened = waitOverlay(true, timeout: 1)
    check(opened && Date().timeIntervalSince(begin) < 0.5, "the trigger still opens while a large file reloads", "(\(Int(Date().timeIntervalSince(begin) * 1000)) ms)")
    closeOverlay()
    for file in (try? fm.contentsOfDirectory(at: templatesDir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: file) }
    pause(0.8)
}

if group("relaunch") {
    quitKeyly()

    freshConfig()
    try? fm.createSymbolicLink(atPath: settingsFile.path, withDestinationPath: work.appendingPathComponent("not-cloned-yet/setting.conf").path)
    _ = launchKeyly()
    check((try? fm.destinationOfSymbolicLink(atPath: settingsFile.path)) != nil, "a broken setting.conf symlink is left alone")
    quitKeyly()

    freshConfig()
    let realTemplates = work.appendingPathComponent("dotfiles-templates")
    try? fm.createDirectory(at: realTemplates, withIntermediateDirectories: true)
    try? fm.removeItem(at: templatesDir)
    try? fm.createSymbolicLink(at: templatesDir, withDestinationURL: realTemplates)
    _ = launchKeyly()
    let start = log.count
    write("# App: KeylyVerifySink\n[Verify]\nX  Through a symlink", to: realTemplates.appendingPathComponent("linked.keyly"))
    check(waitLog("Loaded 1 sheet(s)", after: start), "edits inside a symlinked templates/ reload", "\(log.since(start)) \(templatesDir.resolvingSymlinksInPath().path)")
    quitKeyly()

    try? fm.removeItem(at: configDir)
    let realConfig = work.appendingPathComponent("dotfiles-config")
    try? fm.createDirectory(at: realConfig.appendingPathComponent("templates"), withIntermediateDirectories: true)
    try? fm.createSymbolicLink(at: configDir, withDestinationURL: realConfig)
    _ = launchKeyly()
    let linkedStart = log.count
    write("# App: KeylyVerifySink\n[Verify]\nX  Whole folder linked", to: realConfig.appendingPathComponent("templates/linked.keyly"))
    check(waitLog("Loaded 1 sheet(s)", after: linkedStart), "edits inside a symlinked ~/.config/keyly reload")
    check(keyly?.isRunning == true, "still running at the end")
}

quitKeyly()
logStream.terminate()
sink?.terminate()

let stderrText = (try? String(contentsOf: stderrFile, encoding: .utf8)) ?? ""
check(!stderrText.contains("ThreadSanitizer") && !stderrText.contains("AddressSanitizer"), "no sanitizer reports", String(stderrText.prefix(2000)))

restoreEverything()
check(CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift) == capsLockWasOn, "Caps Lock state unchanged")
try? fm.removeItem(at: work)

print(failures.isEmpty ? "\nAll \(passes) checks passed" : "\n\(failures.count) of \(passes + failures.count) checks failed:\n- " + failures.joined(separator: "\n- "))
exit(failures.isEmpty ? 0 : 1)
