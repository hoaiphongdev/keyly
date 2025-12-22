import Cocoa
import Sparkle

enum UpdateState {
    case none
    case available
    case downloading
    case readyToInstall
}

final class UpdateManager: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateManager()
    
    private var updaterController: SPUStandardUpdaterController?
    private(set) var updateAvailable = false
    private(set) var latestVersion: String?
    private(set) var updateState: UpdateState = .none
    
    var onUpdateAvailable: (() -> Void)?
    var onUpdateStateChanged: ((UpdateState) -> Void)?
    
    private let isDevMode = ProcessInfo.processInfo.environment["KEYLY_DEV"] == "1"
    private let mockUpdate = ProcessInfo.processInfo.environment["KEYLY_MOCK_UPDATE"] == "1"
    
    private var isInsideAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
    
    private override init() {
        super.init()
        
        if isDevMode && mockUpdate {
            updateAvailable = true
            latestVersion = "99.0.0"
            updateState = .available
            return
        }
        
        guard isInsideAppBundle else {
            print("[Keyly] Skipping Sparkle: not running inside .app bundle")
            return
        }
        
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !isDevMode,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }
    
    func checkForUpdates() {
        guard let controller = updaterController else { return }
        controller.checkForUpdates(nil)
    }
    
    func checkForUpdatesInBackground() {
        guard let controller = updaterController,
              controller.updater.canCheckForUpdates else { return }
        controller.updater.checkForUpdatesInBackground()
    }
    
    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }
    
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailable = true
        latestVersion = item.displayVersionString
        updateState = .available
        DispatchQueue.main.async {
            self.onUpdateAvailable?()
            self.onUpdateStateChanged?(.available)
        }
    }
    
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        updateAvailable = false
        latestVersion = nil
        updateState = .none
    }
    
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        updateState = .downloading
        DispatchQueue.main.async {
            self.onUpdateStateChanged?(.downloading)
        }
    }
    
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        updateState = .readyToInstall
        DispatchQueue.main.async {
            self.onUpdateStateChanged?(.readyToInstall)
        }
    }
    
    func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
        updateState = .readyToInstall
        DispatchQueue.main.async {
            self.onUpdateStateChanged?(.readyToInstall)
        }
    }
    
    func simulateDownload(completion: @escaping () -> Void) {
        updateState = .downloading
        onUpdateStateChanged?(.downloading)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.updateState = .readyToInstall
            self.onUpdateStateChanged?(.readyToInstall)
            completion()
        }
    }
    
    func relaunchApp() {
        if isDevMode {
            let url = Bundle.main.bundleURL
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                NSApp.terminate(nil)
            }
        }
    }
}
