import SwiftUI
import AppKit

@main
struct KnockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @State private var settings = Settings.shared
    @State private var engine = KnockEngine.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(settings: settings, engine: engine) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
        } label: {
            // Filled while armed, outlined while paused — readable at a glance.
            Image(systemName: engine.status.isHealthy ? "hand.tap.fill" : "hand.tap")
        }

        Window("Knock の設定", id: "settings") {
            SettingsWindow(settings: settings, engine: engine)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commandsRemoved()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only; no Dock icon, no main window on launch.
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            if !Permissions.hasAccessibility {
                Permissions.requestAccessibility()
            }
            KnockEngine.shared.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            KnockEngine.shared.stop()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
