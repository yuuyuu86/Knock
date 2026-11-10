import AppKit
import Carbon.HIToolbox
import os

/// Executes a bound action.
///
/// Most things are done by posting the key combination macOS already ships with,
/// because that respects whatever the frontmost app expects. The rest goes
/// through AppleScript, `NSWorkspace`, the Accessibility API for window moves, or
/// a short command-line call.
@MainActor
final class ActionRunner {

    private let log = Logger(subsystem: "app.knock", category: "actions")

    /// Reported back so the HUD can say what happened (or why it did not).
    struct Outcome {
        var title: String
        var detail: String?
        var symbol: String
        var isFailure: Bool

        static func ok(_ title: String, _ symbol: String, detail: String? = nil) -> Outcome {
            Outcome(title: title, detail: detail, symbol: symbol, isFailure: false)
        }
        static func failed(_ title: String, _ detail: String) -> Outcome {
            Outcome(title: title, detail: detail, symbol: "exclamationmark.triangle", isFailure: true)
        }
    }

    @discardableResult
    func run(_ action: KnockAction) -> Outcome {
        guard action.kind != .none else {
            return .ok("割り当てなし", "minus.circle")
        }
        if action.kind.needsAccessibility, !Permissions.hasAccessibility {
            return .failed(action.kind.title, "アクセシビリティの許可が必要です")
        }

        let kind = action.kind
        let parameter = action.parameter.trimmingCharacters(in: .whitespacesAndNewlines)
        log.info("run \(kind.rawValue, privacy: .public)")

        switch kind {

        // MARK: screenshots & clipboard
        case .screenshotToClipboard:
            KeySequence(keyCode: kVK_ANSI_4, flags: [.maskControl, .maskShift, .maskCommand]).post()
            return .ok("スクリーンショット", kind.symbol, detail: "クリップボードへ")
        case .screenshotToDesktop:
            KeySequence(keyCode: kVK_ANSI_3, flags: [.maskShift, .maskCommand]).post()
            return .ok("スクリーンショット", kind.symbol, detail: "デスクトップへ保存")
        case .screenshotSelection:
            KeySequence(keyCode: kVK_ANSI_4, flags: [.maskShift, .maskCommand]).post()
            return .ok("範囲を選択", kind.symbol)
        case .copy:
            KeySequence(keyCode: kVK_ANSI_C, flags: .maskCommand).post()
            return .ok("コピー", kind.symbol)
        case .paste:
            KeySequence(keyCode: kVK_ANSI_V, flags: .maskCommand).post()
            return .ok("ペースト", kind.symbol)
        case .pastePlain:
            stripClipboardFormatting()
            KeySequence(keyCode: kVK_ANSI_V, flags: .maskCommand).post()
            return .ok("書式なしでペースト", kind.symbol)
        case .undo:
            KeySequence(keyCode: kVK_ANSI_Z, flags: .maskCommand).post()
            return .ok("取り消し", kind.symbol)
        case .redo:
            KeySequence(keyCode: kVK_ANSI_Z, flags: [.maskShift, .maskCommand]).post()
            return .ok("やり直し", kind.symbol)

        // MARK: media & volume
        case .toggleMute:
            let muted = (runAppleScript("output muted of (get volume settings)") ?? "false") == "true"
            _ = runAppleScript("set volume output muted \(muted ? "false" : "true")")
            return .ok(muted ? "ミュート解除" : "ミュート", muted ? "speaker.wave.2" : "speaker.slash")
        case .volumeUp:
            postMediaKey(NX_KEYTYPE_SOUND_UP)
            return .ok("音量 +", kind.symbol, detail: currentVolumeDescription())
        case .volumeDown:
            postMediaKey(NX_KEYTYPE_SOUND_DOWN)
            return .ok("音量 −", kind.symbol, detail: currentVolumeDescription())
        case .playPause:
            postMediaKey(NX_KEYTYPE_PLAY)
            return .ok("再生 / 一時停止", kind.symbol)
        case .nextTrack:
            postMediaKey(NX_KEYTYPE_NEXT)
            return .ok("次の曲", kind.symbol)
        case .previousTrack:
            postMediaKey(NX_KEYTYPE_PREVIOUS)
            return .ok("前の曲", kind.symbol)

        // MARK: input & display
        case .toggleMicMute:
            let level = Int(runAppleScript("input volume of (get volume settings)") ?? "0") ?? 0
            if level > 0 {
                lastMicLevel = level
                _ = runAppleScript("set volume input volume 0")
                return .ok("マイクをミュート", "mic.slash")
            } else {
                _ = runAppleScript("set volume input volume \(lastMicLevel)")
                return .ok("マイクをオン", "mic")
            }
        case .brightnessUp:
            postMediaKey(NX_KEYTYPE_BRIGHTNESS_UP)
            return .ok("明るさ +", kind.symbol)
        case .brightnessDown:
            postMediaKey(NX_KEYTYPE_BRIGHTNESS_DOWN)
            return .ok("明るさ −", kind.symbol)
        case .keyboardLightUp:
            postMediaKey(NX_KEYTYPE_ILLUMINATION_UP)
            return .ok("キーボード照明 +", kind.symbol)
        case .keyboardLightDown:
            postMediaKey(NX_KEYTYPE_ILLUMINATION_DOWN)
            return .ok("キーボード照明 −", kind.symbol)

        // MARK: window & workspace
        case .missionControl:
            KeySequence(keyCode: kVK_UpArrow, flags: .maskControl).post()
            return .ok("Mission Control", kind.symbol)
        case .spotlight:
            KeySequence(keyCode: kVK_Space, flags: .maskCommand).post()
            return .ok("Spotlight", kind.symbol)
        case .quickNote:
            NSWorkspace.shared.open(URL(string: "mobilenotes://")!)
            return .ok("クイックメモ", kind.symbol)
        case .minimizeWindow:
            KeySequence(keyCode: kVK_ANSI_M, flags: .maskCommand).post()
            return .ok("最小化", kind.symbol)
        case .closeWindow:
            KeySequence(keyCode: kVK_ANSI_W, flags: .maskCommand).post()
            return .ok("ウインドウを閉じる", kind.symbol)
        case .windowLeftHalf:
            return placeFrontWindow(.leftHalf, title: "左半分")
        case .windowRightHalf:
            return placeFrontWindow(.rightHalf, title: "右半分")
        case .maximizeWindow:
            return placeFrontWindow(.full, title: "最大化")
        case .toggleFullScreen:
            KeySequence(keyCode: kVK_ANSI_F, flags: [.maskControl, .maskCommand]).post()
            return .ok("フルスクリーン", kind.symbol)
        case .hideFrontApp:
            NSWorkspace.shared.frontmostApplication?.hide()
            return .ok("アプリを隠す", kind.symbol)
        case .hideOtherApps:
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0 != NSWorkspace.shared.frontmostApplication }
                .forEach { $0.hide() }
            return .ok("ほかを隠す", kind.symbol)
        case .previousSpace:
            KeySequence(keyCode: kVK_LeftArrow, flags: .maskControl).post()
            return .ok("前のスペース", kind.symbol)
        case .nextSpace:
            KeySequence(keyCode: kVK_RightArrow, flags: .maskControl).post()
            return .ok("次のスペース", kind.symbol)
        case .switchToPreviousApp:
            KeySequence(keyCode: kVK_Tab, flags: .maskCommand).post()
            return .ok("直前のアプリ", kind.symbol)
        case .appSwitcherStep:
            stepAppSwitcher()
            return .ok("アプリスイッチャー", kind.symbol)
        case .quitFrontApp:
            KeySequence(keyCode: kVK_ANSI_Q, flags: .maskCommand).post()
            return .ok("アプリを終了", kind.symbol)

        // MARK: lock, sleep & screensaver
        case .lockScreen:
            KeySequence(keyCode: kVK_ANSI_Q, flags: [.maskControl, .maskCommand]).post()
            return .ok("画面をロック", kind.symbol)
        case .startScreenSaver:
            let engine = "/System/Library/CoreServices/ScreenSaverEngine.app"
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: engine),
                                               configuration: NSWorkspace.OpenConfiguration())
            return .ok("スクリーンセーバ", kind.symbol)
        case .sleepDisplay:
            shell("/usr/bin/pmset", ["displaysleepnow"])
            return .ok("ディスプレイをスリープ", kind.symbol)

        // MARK: connectivity
        case .toggleWiFi:
            return toggleWiFi()
        case .toggleBluetooth:
            return toggleBluetooth()
        case .ejectDisks:
            _ = runAppleScript(#"tell application "Finder" to eject (every disk whose ejectable is true)"#)
            return .ok("ディスクを取り出しました", kind.symbol)

        // MARK: system & utilities
        case .emptyTrash:
            _ = runAppleScript(#"tell application "Finder" to empty the trash"#)
            return .ok("ゴミ箱を空にしました", kind.symbol)
        case .batteryStatus:
            return .ok("バッテリー", kind.symbol, detail: batteryDescription())
        case .newEmail:
            NSWorkspace.shared.open(URL(string: "mailto:")!)
            return .ok("新規メール", kind.symbol)
        case .currentWeather:
            let weather = "/System/Applications/Weather.app"
            if FileManager.default.fileExists(atPath: weather) {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: weather),
                                                   configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(URL(string: "https://weather.com")!)
            }
            return .ok("天気", kind.symbol)

        // MARK: custom
        case .pressShortcut:
            guard let sequence = KeySequence(parameter) else {
                return .failed(kind.title, "キーの指定を読み取れませんでした")
            }
            sequence.post()
            return .ok(sequence.display, kind.symbol)
        case .openApplication:
            guard !parameter.isEmpty else { return .failed(kind.title, "アプリが未設定です") }
            let url = parameter.hasPrefix("/")
                ? URL(fileURLWithPath: parameter)
                : NSWorkspace.shared.urlForApplication(withBundleIdentifier: parameter)
                    ?? URL(fileURLWithPath: "/Applications/\(parameter).app")
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .failed(kind.title, "\(parameter) が見つかりません")
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return .ok(url.deletingPathExtension().lastPathComponent, kind.symbol)
        case .openURL:
            guard let url = URL(string: parameter), url.scheme != nil else {
                return .failed(kind.title, "URL が正しくありません")
            }
            NSWorkspace.shared.open(url)
            return .ok(url.host() ?? "URL を開く", kind.symbol)
        case .runAppleShortcut:
            guard !parameter.isEmpty else { return .failed(kind.title, "ショートカットが未設定です") }
            shell("/usr/bin/shortcuts", ["run", parameter])
            return .ok(parameter, kind.symbol, detail: "ショートカットを実行")

        case .none:
            return .ok("割り当てなし", "minus.circle")
        }
    }

    // MARK: - helpers

    private var lastMicLevel = 75

    private func stripClipboardFormatting() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else { return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Media keys travel as `NSSystemDefined` events, not as key codes.
    private func postMediaKey(_ key: Int32) {
        for isDown in [true, false] {
            let data1 = Int((key << 16) | ((isDown ? 0xA : 0xB) << 8))
            guard let event = NSEvent.otherEvent(with: .systemDefined,
                                                 location: .zero,
                                                 modifierFlags: isDown ? NSEvent.ModifierFlags(rawValue: 0xA00)
                                                                       : NSEvent.ModifierFlags(rawValue: 0xB00),
                                                 timestamp: 0,
                                                 windowNumber: 0,
                                                 context: nil,
                                                 subtype: 8,
                                                 data1: data1,
                                                 data2: -1)
            else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// ⌘Tab held long enough for the switcher to appear, then released.
    private func stepAppSwitcher() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let commandDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true),
              let tabDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Tab), keyDown: true),
              let tabUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Tab), keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)
        else { return }
        tabDown.flags = .maskCommand
        tabUp.flags = .maskCommand
        commandDown.post(tap: .cghidEventTap)
        tabDown.post(tap: .cghidEventTap)
        tabUp.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            commandUp.post(tap: .cghidEventTap)
        }
    }

    private enum WindowPlacement { case leftHalf, rightHalf, full }

    /// Moves the frontmost window through the Accessibility API.
    private func placeFrontWindow(_ placement: WindowPlacement, title: String) -> Outcome {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .failed(title, "最前面のアプリが取得できませんでした")
        }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let window = windowValue, CFGetTypeID(window) == AXUIElementGetTypeID()
        else {
            return .failed(title, "ウインドウを取得できませんでした")
        }
        let axWindow = unsafeBitCast(window, to: AXUIElement.self)

        guard let screen = NSScreen.main else { return .failed(title, "画面が見つかりません") }
        let visible = screen.visibleFrame
        // Accessibility uses a top-left origin, NSScreen a bottom-left one.
        let fullHeight = screen.frame.height
        let topInset = fullHeight - visible.maxY

        var origin: CGPoint
        var size: CGSize
        switch placement {
        case .leftHalf:
            origin = CGPoint(x: visible.minX, y: topInset)
            size = CGSize(width: visible.width / 2, height: visible.height)
        case .rightHalf:
            origin = CGPoint(x: visible.midX, y: topInset)
            size = CGSize(width: visible.width / 2, height: visible.height)
        case .full:
            origin = CGPoint(x: visible.minX, y: topInset)
            size = CGSize(width: visible.width, height: visible.height)
        }

        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return .failed(title, "ウインドウを配置できませんでした") }

        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        return .ok(title, "macwindow", detail: app.localizedName)
    }

    private func currentVolumeDescription() -> String? {
        guard let raw = runAppleScript("output volume of (get volume settings)"), let level = Int(raw) else { return nil }
        return "\(level)%"
    }

    private func batteryDescription() -> String {
        let output = shellOutput("/usr/bin/pmset", ["-g", "batt"])
        // A line looks like: "-InternalBattery-0 (id=…)\t82%; discharging; 4:11 remaining"
        guard let field = output
            .split(separator: "\t").last?
            .split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces),
              field.hasSuffix("%")
        else { return "残量を取得できませんでした" }
        let charging = output.contains("AC Power") ? "充電中" : "バッテリー駆動"
        return "\(field) · \(charging)"
    }

    /// Finds the Wi-Fi interface (`en0` on most MacBooks, but not all).
    private func wifiInterfaceName() -> String {
        let ports = shellOutput("/usr/sbin/networksetup", ["-listallhardwareports"])
        let lines = ports.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() where line.contains("Hardware Port: Wi-Fi") {
            for following in lines[(index + 1)...].prefix(3) where following.hasPrefix("Device: ") {
                return String(following.dropFirst("Device: ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return "en0"
    }

    private func toggleWiFi() -> Outcome {
        let interface = wifiInterfaceName()

        let state = shellOutput("/usr/sbin/networksetup", ["-getairportpower", interface])
        let isOn = state.contains("On")
        shell("/usr/sbin/networksetup", ["-setairportpower", interface, isOn ? "off" : "on"])
        return .ok(isOn ? "Wi‑Fi オフ" : "Wi‑Fi オン", "wifi", detail: interface)
    }

    private func toggleBluetooth() -> Outcome {
        // `blueutil` is the only reliable non-interactive switch; without it we
        // send the user to the Bluetooth pane rather than pretend it worked.
        for path in ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"] where FileManager.default.isExecutableFile(atPath: path) {
            let state = shellOutput(path, ["-p"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let isOn = state == "1"
            shell(path, ["-p", isOn ? "0" : "1"])
            return .ok(isOn ? "Bluetooth オフ" : "Bluetooth オン", "dot.radiowaves.right")
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Bluetooth-Settings.extension")!)
        return .failed("Bluetooth", "blueutil が必要です。設定を開きました")
    }

    // MARK: process & script plumbing

    @discardableResult
    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { log.error("applescript failed: \(String(describing: error), privacy: .public)") }
        return result?.stringValue
    }

    private func shell(_ path: String, _ arguments: [String]) {
        _ = shellOutput(path, arguments)
    }

    @discardableResult
    private func shellOutput(_ path: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            log.error("\(path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return ""
        }
    }
}

// Media key identifiers from IOKit's HID system, spelled out so the file does
// not need the private `IOKit/hidsystem/ev_keymap.h` import.
private let NX_KEYTYPE_SOUND_UP: Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
private let NX_KEYTYPE_MUTE: Int32 = 7
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18
private let NX_KEYTYPE_ILLUMINATION_UP: Int32 = 21
private let NX_KEYTYPE_ILLUMINATION_DOWN: Int32 = 22
