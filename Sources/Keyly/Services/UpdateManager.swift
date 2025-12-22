import Foundation
import Sparkle

final class UpdateManager: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateManager()
    
    private var updaterController: SPUStandardUpdaterController?
    private(set) var updateAvailable = false
    private(set) var latestVersion: String?
    
    var onUpdateAvailable: (() -> Void)?
    
    private let isDevMode = ProcessInfo.processInfo.environment["KEYLY_DEV"] == "1"
    private let mockUpdate = ProcessInfo.processInfo.environment["KEYLY_MOCK_UPDATE"] == "1"
    
    private override init() {
        super.init()
        
        if isDevMode && mockUpdate {
            updateAvailable = true
            latestVersion = "99.0.0"
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
        DispatchQueue.main.async {
            self.onUpdateAvailable?()
        }
    }
    
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        updateAvailable = false
        latestVersion = nil
    }
    
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        updateAvailable = false
    }
}
