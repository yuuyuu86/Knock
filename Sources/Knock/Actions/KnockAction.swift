import Foundation

/// Everything a knock can be bound to.
///
/// Cases that need a value the user picks (an app, a URL, a shortcut name, a key
/// combination) carry it in `KnockAction.parameter` rather than as an associated
/// value, which keeps the whole binding trivially `Codable`.
enum ActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case none

    // Screenshots & clipboard
    case screenshotToClipboard, screenshotToDesktop, screenshotSelection
    case copy, paste, pastePlain, undo, redo

    // Media & volume
    case toggleMute, volumeUp, volumeDown, playPause, nextTrack, previousTrack

    // Input, display & focus
    case toggleMicMute, brightnessUp, brightnessDown, keyboardLightUp, keyboardLightDown

    // Window & workspace
    case missionControl, spotlight, quickNote, minimizeWindow, closeWindow
    case windowLeftHalf, windowRightHalf, maximizeWindow, toggleFullScreen
    case hideFrontApp, hideOtherApps, previousSpace, nextSpace
    case switchToPreviousApp, appSwitcherStep, quitFrontApp

    // Lock, sleep & screensaver
    case lockScreen, startScreenSaver, sleepDisplay

    // Connectivity
    case toggleWiFi, toggleBluetooth, ejectDisks

    // System status & utilities
    case emptyTrash, batteryStatus, newEmail, currentWeather

    // Custom
    case pressShortcut, openApplication, openURL, runAppleShortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:                 "なし"
        case .screenshotToClipboard:"スクリーンショット → クリップボード"
        case .screenshotToDesktop:  "スクリーンショット → デスクトップ"
        case .screenshotSelection:  "スクリーンショット（範囲選択）"
        case .copy:                 "コピー（⌘C）"
        case .paste:                "ペースト（⌘V）"
        case .pastePlain:           "書式なしでペースト"
        case .undo:                 "取り消す（⌘Z）"
        case .redo:                 "やり直す（⇧⌘Z）"
        case .toggleMute:           "ミュート / 解除"
        case .volumeUp:             "音量を上げる"
        case .volumeDown:           "音量を下げる"
        case .playPause:            "再生 / 一時停止"
        case .nextTrack:            "次の曲へ"
        case .previousTrack:        "前の曲へ"
        case .toggleMicMute:        "マイクのミュート / 解除"
        case .brightnessUp:         "画面の明るさを上げる"
        case .brightnessDown:       "画面の明るさを下げる"
        case .keyboardLightUp:      "キーボードバックライトを上げる"
        case .keyboardLightDown:    "キーボードバックライトを下げる"
        case .missionControl:       "Mission Control"
        case .spotlight:            "Spotlight 検索"
        case .quickNote:            "クイックメモ"
        case .minimizeWindow:       "最前面のウインドウを最小化"
        case .closeWindow:          "最前面のウインドウを閉じる"
        case .windowLeftHalf:       "ウインドウを左半分へ"
        case .windowRightHalf:      "ウインドウを右半分へ"
        case .maximizeWindow:       "ウインドウを最大化"
        case .toggleFullScreen:     "フルスクリーン切り替え"
        case .hideFrontApp:         "最前面のアプリを隠す"
        case .hideOtherApps:        "ほかのアプリを隠す"
        case .previousSpace:        "前のスペースへ"
        case .nextSpace:            "次のスペースへ"
        case .switchToPreviousApp:  "直前のアプリに切り替え"
        case .appSwitcherStep:      "アプリスイッチャー（叩いて送る）"
        case .quitFrontApp:         "最前面のアプリを終了"
        case .lockScreen:           "画面をロック"
        case .startScreenSaver:     "スクリーンセーバを開始"
        case .sleepDisplay:         "ディスプレイをスリープ"
        case .toggleWiFi:           "Wi‑Fi のオン / オフ"
        case .toggleBluetooth:      "Bluetooth のオン / オフ"
        case .ejectDisks:           "外部ディスクを取り出す"
        case .emptyTrash:           "ゴミ箱を空にする"
        case .batteryStatus:        "バッテリー残量を表示"
        case .newEmail:             "新規メールを作成"
        case .currentWeather:       "天気を開く"
        case .pressShortcut:        "キーボードショートカットを送る…"
        case .openApplication:      "アプリケーションを開く…"
        case .openURL:              "URL を開く…"
        case .runAppleShortcut:     "Apple ショートカットを実行…"
        }
    }

    var symbol: String {
        switch self {
        case .none:                 "minus.circle"
        case .screenshotToClipboard,
             .screenshotToDesktop,
             .screenshotSelection:  "camera"
        case .copy:                 "doc.on.doc"
        case .paste, .pastePlain:   "doc.on.clipboard"
        case .undo:                 "arrow.uturn.backward"
        case .redo:                 "arrow.uturn.forward"
        case .toggleMute:           "speaker.slash"
        case .volumeUp:             "speaker.wave.3"
        case .volumeDown:           "speaker.wave.1"
        case .playPause:            "playpause"
        case .nextTrack:            "forward.end"
        case .previousTrack:        "backward.end"
        case .toggleMicMute:        "mic.slash"
        case .brightnessUp:         "sun.max"
        case .brightnessDown:       "sun.min"
        case .keyboardLightUp:      "keyboard.badge.ellipsis"
        case .keyboardLightDown:    "keyboard"
        case .missionControl:       "square.grid.3x2"
        case .spotlight:            "magnifyingglass"
        case .quickNote:            "note.text"
        case .minimizeWindow:       "minus.rectangle"
        case .closeWindow:          "xmark.rectangle"
        case .windowLeftHalf:       "rectangle.lefthalf.filled"
        case .windowRightHalf:      "rectangle.righthalf.filled"
        case .maximizeWindow:       "rectangle.expand.vertical"
        case .toggleFullScreen:     "arrow.up.left.and.arrow.down.right"
        case .hideFrontApp:         "eye.slash"
        case .hideOtherApps:        "rectangle.on.rectangle.slash"
        case .previousSpace:        "chevron.left.square"
        case .nextSpace:            "chevron.right.square"
        case .switchToPreviousApp:  "arrow.left.arrow.right.square"
        case .appSwitcherStep:      "square.stack"
        case .quitFrontApp:         "power"
        case .lockScreen:           "lock"
        case .startScreenSaver:     "display"
        case .sleepDisplay:         "moon"
        case .toggleWiFi:           "wifi"
        case .toggleBluetooth:      "dot.radiowaves.right"
        case .ejectDisks:           "eject"
        case .emptyTrash:           "trash"
        case .batteryStatus:        "battery.75"
        case .newEmail:             "envelope"
        case .currentWeather:       "cloud.sun"
        case .pressShortcut:        "command"
        case .openApplication:      "app.badge"
        case .openURL:              "link"
        case .runAppleShortcut:     "bolt"
        }
    }

    /// Label for the value this action needs, or nil when it takes none.
    var parameterPrompt: String? {
        switch self {
        case .pressShortcut:    "送るキー（例: cmd shift 4）"
        case .openApplication:  "アプリ名（例: Safari）"
        case .openURL:          "URL（例: https://example.com）"
        case .runAppleShortcut: "ショートカット名"
        default: nil
        }
    }

    var needsAccessibility: Bool {
        switch self {
        case .copy, .paste, .pastePlain, .undo, .redo,
             .screenshotToClipboard, .screenshotToDesktop, .screenshotSelection,
             .missionControl, .spotlight, .quickNote,
             .minimizeWindow, .closeWindow, .toggleFullScreen,
             .hideFrontApp, .hideOtherApps, .previousSpace, .nextSpace,
             .switchToPreviousApp, .appSwitcherStep, .quitFrontApp,
             .lockScreen, .pressShortcut,
             .windowLeftHalf, .windowRightHalf, .maximizeWindow:
            true
        default:
            false
        }
    }

    var category: ActionCategory {
        switch self {
        case .none: .none
        case .screenshotToClipboard, .screenshotToDesktop, .screenshotSelection,
             .copy, .paste, .pastePlain, .undo, .redo: .clipboard
        case .toggleMute, .volumeUp, .volumeDown, .playPause, .nextTrack, .previousTrack: .media
        case .toggleMicMute, .brightnessUp, .brightnessDown, .keyboardLightUp, .keyboardLightDown: .input
        case .missionControl, .spotlight, .quickNote, .minimizeWindow, .closeWindow,
             .windowLeftHalf, .windowRightHalf, .maximizeWindow, .toggleFullScreen,
             .hideFrontApp, .hideOtherApps, .previousSpace, .nextSpace,
             .switchToPreviousApp, .appSwitcherStep, .quitFrontApp: .window
        case .lockScreen, .startScreenSaver, .sleepDisplay: .lock
        case .toggleWiFi, .toggleBluetooth, .ejectDisks: .connectivity
        case .emptyTrash, .batteryStatus, .newEmail, .currentWeather: .system
        case .pressShortcut, .openApplication, .openURL, .runAppleShortcut: .custom
        }
    }
}

enum ActionCategory: String, CaseIterable, Identifiable, Sendable {
    case none, clipboard, media, input, window, lock, connectivity, system, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:         "割り当てなし"
        case .clipboard:    "スクリーンショットとクリップボード"
        case .media:        "メディアと音量"
        case .input:        "入力・ディスプレイ"
        case .window:       "ウインドウとスペース"
        case .lock:         "ロック・スリープ"
        case .connectivity: "接続"
        case .system:       "システムとユーティリティ"
        case .custom:       "カスタム"
        }
    }

    var symbol: String {
        switch self {
        case .none:         "minus.circle"
        case .clipboard:    "camera"
        case .media:        "play.circle"
        case .input:        "slider.horizontal.3"
        case .window:       "macwindow"
        case .lock:         "lock"
        case .connectivity: "wifi"
        case .system:       "gearshape"
        case .custom:       "bolt"
        }
    }

    var actions: [ActionKind] { ActionKind.allCases.filter { $0.category == self } }
}

/// A binding: what to do, plus the value the action needs.
struct KnockAction: Codable, Equatable, Sendable {
    var kind: ActionKind = .none
    var parameter: String = ""

    static let empty = KnockAction()

    var displayName: String {
        guard kind.parameterPrompt != nil, !parameter.isEmpty else { return kind.title }
        switch kind {
        case .pressShortcut:    return "キー送信: \(KeySequence(parameter)?.display ?? parameter)"
        case .openApplication:  return "\(parameter) を開く"
        case .openURL:          return "\(parameter) を開く"
        case .runAppleShortcut: return "ショートカット: \(parameter)"
        default:                return kind.title
        }
    }

    var isConfigured: Bool {
        guard kind != .none else { return false }
        guard kind.parameterPrompt != nil else { return true }
        return !parameter.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
