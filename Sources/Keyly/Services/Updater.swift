import Cocoa
import Sparkle
import UserNotifications

/// Wraps Sparkle. Keyly is a menu bar app (LSUIElement), so scheduled updates are
/// surfaced "gently": a badge on the status item, a menu entry and a notification,
/// instead of a window popping up over whatever the user is doing.
final class Updater: NSObject {
    static let shared = Updater()

    /// Called with the pending version, or nil once the update session ends.
    var onPendingUpdateChanged: ((String?) -> Void)?

    private(set) var pendingVersion: String?

    private let isDevMode = ProcessInfo.processInfo.environment["KEYLY_DEV"] == "1"
    private let notificationId = "keyly.update.available"
    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: !isDevMode,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func start() {
        _ = controller
    }

    var canCheckForUpdates: Bool {
        !isDevMode && controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        guard !isDevMode else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    private func setPendingVersion(_ version: String?) {
        guard pendingVersion != version else { return }
        pendingVersion = version
        onPendingUpdateChanged?(version)
    }

    private func postNotification(version: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Keyly \(version) is available"
            content.body = "Click to update. You can also use \"Update to \(version)…\" in the menu bar."
            let request = UNNotificationRequest(identifier: self.notificationId, content: content, trigger: nil)
            center.add(request)
        }
    }

    private func removeNotification() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationId])
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        setPendingVersion(update.displayVersionString)
        if !handleShowingUpdate && !state.userInitiated {
            postNotification(version: update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        removeNotification()
    }

    func standardUserDriverWillFinishUpdateSession() {
        setPendingVersion(nil)
        removeNotification()
    }
}

extension Updater: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { self.checkForUpdates() }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
