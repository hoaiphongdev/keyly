import Foundation

final class FileWatcher {
    private var streamRef: FSEventStreamRef?
    private let paths: [String]
    private let callback: () -> Void
    private var lastEventTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.5
    
    init(paths: [String], callback: @escaping () -> Void) {
        self.paths = paths
        self.callback = callback
    }
    
    func start() {
        guard streamRef == nil else { return }
        
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handleEvents()
        }
        
        streamRef = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
        
        guard let stream = streamRef else { return }
        
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }
    
    func stop() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }
    
    private func handleEvents() {
        let now = Date()
        guard now.timeIntervalSince(lastEventTime) > debounceInterval else { return }
        lastEventTime = now
        
        DispatchQueue.main.async { [weak self] in
            self?.callback()
        }
    }
    
    deinit {
        stop()
    }
}

