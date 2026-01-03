import Cocoa

// MARK: - Update Feature Disabled
// Set to true to re-enable update functionality
let UPDATE_FEATURE_ENABLED = false

enum UpdateState {
    case none
    case checking
    case available
    case downloading(progress: Double)
    case readyToInstall
    case error(String)
}

struct GitHubRelease: Codable {
    let tagName: String
    let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

final class UpdateManager: NSObject {
    static let shared = UpdateManager()
    
    private(set) var updateAvailable = false
    private(set) var latestVersion: String?
    private(set) var downloadUrl: String?
    private(set) var updateState: UpdateState = .none
    
    var onUpdateAvailable: (() -> Void)?
    var onUpdateStateChanged: ((UpdateState) -> Void)?
    
    private let isDevMode = ProcessInfo.processInfo.environment["KEYLY_DEV"] == "1"
    private let mockUpdate = ProcessInfo.processInfo.environment["KEYLY_MOCK_UPDATE"] == "1"
    
    private let githubRepo = "hoaiphongdev/keyly"
    private let checkIntervalSeconds: TimeInterval = 2 * 24 * 60 * 60
    private let lastCheckKey = "KeylyLastUpdateCheck"
    
    private var downloadTask: URLSessionDownloadTask?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()
    
    private var lastCheckDate: Date? {
        get { UserDefaults.standard.object(forKey: lastCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCheckKey) }
    }
    
    private var shouldCheckForUpdates: Bool {
        guard let lastCheck = lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) >= checkIntervalSeconds
    }
    
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var appPath: String {
        Bundle.main.bundleURL.path
    }
    
    private override init() {
        super.init()
        
        if isDevMode && mockUpdate {
            updateAvailable = true
            latestVersion = "99.0.0"
            downloadUrl = "https://example.com/mock.dmg"
            updateState = .available
        }
    }
    
    var canCheckForUpdates: Bool {
        // Update feature temporarily disabled
        if !UPDATE_FEATURE_ENABLED { return false }
        
        if isDevMode && !mockUpdate { return false }
        if case .checking = updateState { return false }
        if case .downloading = updateState { return false }
        return true
    }
    
    func checkForUpdates() {
        // Update feature temporarily disabled
        guard UPDATE_FEATURE_ENABLED else { return }
        guard canCheckForUpdates else { return }
        
        if isDevMode && mockUpdate {
            updateAvailable = true
            latestVersion = "99.0.0"
            updateState = .available
            DispatchQueue.main.async {
                self.onUpdateAvailable?()
                self.onUpdateStateChanged?(.available)
            }
            showUpdateAlert()
            return
        }
        
        updateState = .checking
        onUpdateStateChanged?(.checking)
        
        fetchLatestRelease { [weak self] result in
            self?.lastCheckDate = Date()
            self?.handleCheckResult(result, showAlert: true)
        }
    }
    
    func checkForUpdatesInBackground() {
        // Update feature temporarily disabled
        guard UPDATE_FEATURE_ENABLED else { return }
        guard canCheckForUpdates else { return }
        guard !isDevMode || mockUpdate else { return }
        guard shouldCheckForUpdates else { return }
        
        if mockUpdate {
        updateAvailable = true
            latestVersion = "99.0.0"
        updateState = .available
        DispatchQueue.main.async {
            self.onUpdateAvailable?()
            self.onUpdateStateChanged?(.available)
            }
            return
        }
        
        fetchLatestRelease { [weak self] result in
            self?.lastCheckDate = Date()
            self?.handleCheckResult(result, showAlert: false)
        }
    }
    
    private func fetchLatestRelease(completion: @escaping (Result<GitHubRelease, Error>) -> Void) {
        let urlString = "https://api.github.com/repos/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            completion(.failure(UpdateError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(UpdateError.noData))
                    return
                }
                
                do {
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    completion(.success(release))
                } catch {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    private func handleCheckResult(_ result: Result<GitHubRelease, Error>, showAlert: Bool) {
        switch result {
        case .success(let release):
            let version = release.tagName.hasPrefix("v") 
                ? String(release.tagName.dropFirst()) 
                : release.tagName
            
            let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
            
            latestVersion = version
            downloadUrl = dmgAsset?.browserDownloadUrl
            updateAvailable = isVersionNewer(version, than: currentVersion)
            
            if updateAvailable {
                updateState = .available
                onUpdateAvailable?()
                onUpdateStateChanged?(.available)
                if showAlert {
                    showUpdateAlert()
                }
            } else {
                updateState = .none
                onUpdateStateChanged?(.none)
                if showAlert {
                    showNoUpdateAlert()
                }
            }
            
        case .failure(let error):
            updateState = .error(error.localizedDescription)
            onUpdateStateChanged?(updateState)
            if showAlert {
                showErrorAlert(error)
            }
        }
    }
    
    private func isVersionNewer(_ new: String, than current: String) -> Bool {
        let newParts = new.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(newParts.count, currentParts.count) {
            let newPart = i < newParts.count ? newParts[i] : 0
            let currentPart = i < currentParts.count ? currentParts[i] : 0
            
            if newPart > currentPart { return true }
            if newPart < currentPart { return false }
        }
        return false
    }
    
    func performUpdate() {
        // Update feature temporarily disabled
        guard UPDATE_FEATURE_ENABLED else { return }
        guard let urlString = downloadUrl, let url = URL(string: urlString) else { return }
        
        if isDevMode && mockUpdate {
            simulateDownload { }
            return
        }
        
        updateState = .downloading(progress: 0)
        onUpdateStateChanged?(updateState)
        
        downloadTask = urlSession.downloadTask(with: url)
        downloadTask?.resume()
    }
    
    private func installUpdate(from tempURL: URL) {
        let fileManager = FileManager.default
        
        do {
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let dmgPath = tempDir.appendingPathComponent("Keyly.dmg")
            try fileManager.moveItem(at: tempURL, to: dmgPath)
            
            let mountPoint = tempDir.appendingPathComponent("mount")
            try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            
            let mountProcess = Process()
            mountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            mountProcess.arguments = ["attach", dmgPath.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet"]
            try mountProcess.run()
            mountProcess.waitUntilExit()
            
            guard mountProcess.terminationStatus == 0 else {
                throw UpdateError.mountFailed
            }
            
            let contents = try fileManager.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.noAppInDMG
            }
            
            let appURL = URL(fileURLWithPath: appPath)
            let backupURL = appURL.deletingLastPathComponent().appendingPathComponent("Keyly.app.backup")
            
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: appURL, to: backupURL)
            
            do {
                try fileManager.copyItem(at: newApp, to: appURL)
                try fileManager.removeItem(at: backupURL)
            } catch {
                try? fileManager.moveItem(at: backupURL, to: appURL)
                throw error
            }
            
            let unmountProcess = Process()
            unmountProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            unmountProcess.arguments = ["detach", mountPoint.path, "-quiet"]
            try? unmountProcess.run()
            unmountProcess.waitUntilExit()
            
            try? fileManager.removeItem(at: tempDir)
            
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-dr", "com.apple.quarantine", appPath]
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()
            
        updateState = .readyToInstall
            onUpdateStateChanged?(.readyToInstall)
            
            relaunchApp()
            
        } catch {
            updateState = .error(error.localizedDescription)
            onUpdateStateChanged?(updateState)
        }
    }
    
    func simulateDownload(completion: @escaping () -> Void) {
        updateState = .downloading(progress: 0)
        onUpdateStateChanged?(.downloading(progress: 0))
        
        var progress = 0.0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            progress += 0.05
            if progress >= 1.0 {
                timer.invalidate()
                self?.updateState = .readyToInstall
                self?.onUpdateStateChanged?(.readyToInstall)
            completion()
            } else {
                self?.updateState = .downloading(progress: progress)
                self?.onUpdateStateChanged?(.downloading(progress: progress))
            }
        }
    }
    
    func relaunchApp() {
            let url = Bundle.main.bundleURL
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                NSApp.terminate(nil)
            }
    }
    
    private func showUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Version \(latestVersion ?? "unknown") is available. Would you like to update now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        
        if let iconURL = Bundle.module.url(forResource: "keyly", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 64, height: 64)
            alert.icon = icon
        }
        
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        
        if alert.runModal() == .alertFirstButtonReturn {
            performUpdate()
        }
    }
    
    private func showNoUpdateAlert() {
        let alert = NSAlert()
        alert.messageText = "No Updates Available"
        alert.informativeText = "You're running the latest version (\(currentVersion))."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        if let iconURL = Bundle.module.url(forResource: "keyly", withExtension: "png"),
           let icon = NSImage(contentsOf: iconURL) {
            icon.size = NSSize(width: 64, height: 64)
            alert.icon = icon
        }
        
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    
    private func showErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not check for updates. Please try again later."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

extension UpdateManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        installUpdate(from: location)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        updateState = .downloading(progress: progress)
        onUpdateStateChanged?(updateState)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            updateState = .error(error.localizedDescription)
            onUpdateStateChanged?(updateState)
        }
    }
}

enum UpdateError: LocalizedError {
    case invalidURL
    case noData
    case mountFailed
    case noAppInDMG
    case installFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noData: return "No data received"
        case .mountFailed: return "Failed to mount DMG"
        case .noAppInDMG: return "No app found in DMG"
        case .installFailed: return "Failed to install update"
        }
    }
}



