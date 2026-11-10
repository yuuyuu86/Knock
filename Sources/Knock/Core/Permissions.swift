import AppKit
import ApplicationServices

/// Accessibility is what lets Knock post key events and move windows.
enum Permissions {

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt. macOS only displays it once per binary, so the
    /// settings pane also offers a direct link to the pane.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}
