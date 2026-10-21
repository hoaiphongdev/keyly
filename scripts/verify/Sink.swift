import Cocoa

final class SinkDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About KeylyVerifySink", action: nil, keyEquivalent: ""))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Sink Action", action: #selector(noop), keyEquivalent: "j"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu

        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 320, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Keyly verify sink"
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func noop() {}
}

let app = NSApplication.shared
let delegate = SinkDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
