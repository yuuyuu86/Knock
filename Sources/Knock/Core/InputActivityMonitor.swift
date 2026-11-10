import AppKit

/// Watches for typing and trackpad use so the detector can ignore the shake
/// those produce. Global monitors need Accessibility, which Knock asks for
/// anyway; without it the monitor simply never fires and detection still works.
@MainActor
final class InputActivityMonitor {

    private(set) var lastActivity: TimeInterval = -.infinity
    private var monitors: [Any] = []

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .flagsChanged,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .scrollWheel, .gesture, .magnify, .swipe,
        ]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.lastActivity = ProcessInfo.processInfo.systemUptime
        }) {
            monitors.append(global)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.lastActivity = ProcessInfo.processInfo.systemUptime
            return event
        }
        if let local { monitors.append(local) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    deinit {
        let captured = monitors
        Task { @MainActor in captured.forEach(NSEvent.removeMonitor) }
    }
}
