import Cocoa

enum UpdateState {
    case none
    case checking
    case available
    case downloading
    case readyToInstall
    case error(String)
}

struct UpdateInfo: Codable {
    let updateAvailable: Bool
    let currentVersion: String
    let latestVersion: String
    let downloadUrl: String?
    let fileSize: Int?
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
    
    private var checkTask: Process?
    private var updateTask: Process?
    
    // 2 days
    private let checkIntervalSeconds: TimeInterval = 2 * 24 * 60 * 60
    private let lastCheckKey = "KeylyLastUpdateCheck"
    
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
    
    private var isInsideAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
    
    private var scriptsPath: URL? {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/scripts")
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
        if isDevMode && !mockUpdate {
            return false
        }
        if case .checking = updateState { return false }
        if case .downloading = updateState { return false }
        return true
    }
    
    func checkForUpdates() {
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
        
        performUpdateCheck { [weak self] result in
            DispatchQueue.main.async {
                self?.lastCheckDate = Date()
                self?.handleCheckResult(result, showAlert: true)
            }
        }
    }
    
    func checkForUpdatesInBackground() {
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
        
        performUpdateCheck { [weak self] result in
            DispatchQueue.main.async {
                self?.lastCheckDate = Date()
                self?.handleCheckResult(result, showAlert: false)
            }
        }
    }
    
    private func performUpdateCheck(completion: @escaping (Result<UpdateInfo, Error>) -> Void) {
        let scriptPath = getScriptPath("check-update.sh")
        
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            runCheckUpdateScript(version: currentVersion, completion: completion)
            return
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath, currentVersion]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        checkTask = task
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                if task.terminationStatus == 0 {
                    let updateInfo = try JSONDecoder().decode(UpdateInfo.self, from: data)
                    completion(.success(updateInfo))
                } else if task.terminationStatus == 1 {
                    let updateInfo = try? JSONDecoder().decode(UpdateInfo.self, from: data)
                    if let info = updateInfo {
                        completion(.success(info))
                    } else {
                        completion(.failure(UpdateError.noUpdate))
                    }
                } else {
                    completion(.failure(UpdateError.networkError))
                }
            } catch {
                completion(.failure(error))
            }
            
            self?.checkTask = nil
        }
    }
    
    private func runCheckUpdateScript(version: String, completion: @escaping (Result<UpdateInfo, Error>) -> Void) {
        let script = """
        GITHUB_REPO="hoaiphongdev/keyly"
        CURRENT_VERSION="\(version)"
        
        RELEASE_JSON=$(curl -sS --connect-timeout 10 --max-time 30 \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null) || exit 2
        
        TAG_NAME=$(echo "$RELEASE_JSON" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"//;s/"$//' || echo "")
        LATEST_VERSION=$(echo "$TAG_NAME" | sed 's/^v//')
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*\\.dmg"' | head -1 | sed 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"//;s/"$//' || echo "")
        
        version_gt() {
            local IFS=.
            local i ver1=($1) ver2=($2)
            for ((i=0; i<${#ver1[@]} || i<${#ver2[@]}; i++)); do
                local v1=${ver1[i]:-0}
                local v2=${ver2[i]:-0}
                if ((v1 > v2)); then return 0; fi
                if ((v1 < v2)); then return 1; fi
            done
            return 1
        }
        
        if version_gt "$LATEST_VERSION" "$CURRENT_VERSION"; then
            echo "{\\"updateAvailable\\": true, \\"currentVersion\\": \\"$CURRENT_VERSION\\", \\"latestVersion\\": \\"$LATEST_VERSION\\", \\"downloadUrl\\": \\"$DOWNLOAD_URL\\"}"
            exit 0
        else
            echo "{\\"updateAvailable\\": false, \\"currentVersion\\": \\"$CURRENT_VERSION\\", \\"latestVersion\\": \\"$LATEST_VERSION\\"}"
            exit 1
        fi
        """
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        DispatchQueue.global(qos: .utility).async {
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                if let updateInfo = try? JSONDecoder().decode(UpdateInfo.self, from: data) {
                    completion(.success(updateInfo))
                } else {
                    completion(.failure(UpdateError.parseError))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    private func handleCheckResult(_ result: Result<UpdateInfo, Error>, showAlert: Bool) {
        switch result {
        case .success(let info):
            updateAvailable = info.updateAvailable
            latestVersion = info.latestVersion
            downloadUrl = info.downloadUrl
            
            if info.updateAvailable {
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
    
    func performUpdate() {
        guard let url = downloadUrl else { return }
        
        if isDevMode && mockUpdate {
            simulateDownload { }
            return
        }
        
        updateState = .downloading
        onUpdateStateChanged?(.downloading)
        
        let scriptPath = getScriptPath("perform-update.sh")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        if FileManager.default.fileExists(atPath: scriptPath) {
            task.arguments = [scriptPath, url, appPath]
        } else {
            task.arguments = ["-c", getEmbeddedUpdateScript(downloadUrl: url, appPath: appPath)]
        }
        
        updateTask = task
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try task.run()
                task.waitUntilExit()
                
                DispatchQueue.main.async {
                    if task.terminationStatus == 0 {
                        self?.updateState = .readyToInstall
                        self?.onUpdateStateChanged?(.readyToInstall)
                        NSApp.terminate(nil)
                    } else {
                        self?.updateState = .error("Update failed")
                        self?.onUpdateStateChanged?(self?.updateState ?? .none)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.updateState = .error(error.localizedDescription)
                    self?.onUpdateStateChanged?(self?.updateState ?? .none)
                }
            }
            
            self?.updateTask = nil
        }
    }
    
    private func getEmbeddedUpdateScript(downloadUrl: String, appPath: String) -> String {
        return """
        set -euo pipefail
        
        DOWNLOAD_URL="\(downloadUrl)"
        APP_PATH="\(appPath)"
        
        TEMP_DIR=$(mktemp -d)
        DMG_PATH="$TEMP_DIR/Keyly.dmg"
        MOUNT_POINT="$TEMP_DIR/mount"
        
        cleanup() {
            if [[ -d "$MOUNT_POINT" ]]; then
                hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
            fi
            rm -rf "$TEMP_DIR"
        }
        trap cleanup EXIT
        
        curl -L --progress-bar --connect-timeout 30 --max-time 300 -o "$DMG_PATH" "$DOWNLOAD_URL" || exit 1
        
        mkdir -p "$MOUNT_POINT"
        hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -quiet || exit 1
        
        NEW_APP=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -1)
        [[ -z "$NEW_APP" ]] && exit 1
        
        BACKUP_PATH="${APP_PATH}.backup"
        [[ -d "$APP_PATH" ]] && { rm -rf "$BACKUP_PATH"; mv "$APP_PATH" "$BACKUP_PATH"; }
        
        cp -R "$NEW_APP" "$APP_PATH" || { [[ -d "$BACKUP_PATH" ]] && mv "$BACKUP_PATH" "$APP_PATH"; exit 1; }
        
        rm -rf "$BACKUP_PATH"
        xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
        
        open -n "$APP_PATH" &
        sleep 1
        exit 0
        """
    }
    
    private func getScriptPath(_ scriptName: String) -> String {
        if let resourcePath = Bundle.main.resourcePath {
            let bundledPath = (resourcePath as NSString).appendingPathComponent("scripts/\(scriptName)")
            if FileManager.default.fileExists(atPath: bundledPath) {
                return bundledPath
            }
        }
        
        let projectPath = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/\(scriptName)")
            .path
        
        return projectPath
    }
    
    func simulateDownload(completion: @escaping () -> Void) {
        updateState = .downloading
        onUpdateStateChanged?(.downloading)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.updateState = .readyToInstall
            self?.onUpdateStateChanged?(.readyToInstall)
            completion()
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

enum UpdateError: LocalizedError {
    case noUpdate
    case networkError
    case parseError
    case installFailed
    
    var errorDescription: String? {
        switch self {
        case .noUpdate: return "No update available"
        case .networkError: return "Network error"
        case .parseError: return "Failed to parse update info"
        case .installFailed: return "Failed to install update"
        }
    }
}
