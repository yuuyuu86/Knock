import Foundation
import Carbon.HIToolbox

/// A key combination written as plain text, e.g. `"cmd shift 4"` or `"ctrl up"`.
struct KeySequence {
    var keyCode: CGKeyCode
    var flags: CGEventFlags
    var display: String

    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "⌘": .maskCommand,
        "shift": .maskShift, "⇧": .maskShift,
        "opt": .maskAlternate, "option": .maskAlternate, "alt": .maskAlternate, "⌥": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl, "⌃": .maskControl,
        "fn": .maskSecondaryFn,
    ]

    private static let namedKeys: [String: Int] = [
        "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab,
        "esc": kVK_Escape, "escape": kVK_Escape, "delete": kVK_Delete, "backspace": kVK_Delete,
        "up": kVK_UpArrow, "down": kVK_DownArrow, "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6,
        "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]

    private static let characterKeys: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
        "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
        "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
        "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
        "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
        "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        ".": kVK_ANSI_Period, ",": kVK_ANSI_Comma, "/": kVK_ANSI_Slash, "-": kVK_ANSI_Minus,
        "=": kVK_ANSI_Equal, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, "`": kVK_ANSI_Grave,
        "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "\\": kVK_ANSI_Backslash,
    ]

    init?(_ text: String) {
        let tokens = text
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "+" || $0 == "-" && text.count > 1 })
            .map(String.init)
        guard !tokens.isEmpty else { return nil }

        var flags = CGEventFlags()
        var key: Int?
        var shown: [String] = []

        for token in tokens {
            if let modifier = Self.modifiers[token] {
                flags.insert(modifier)
                shown.append(Self.glyph(for: modifier))
            } else if let named = Self.namedKeys[token] {
                key = named
                shown.append(token)
            } else if token.count == 1, let character = token.first, let code = Self.characterKeys[character] {
                key = code
                shown.append(token.uppercased())
            }
        }
        guard let key else { return nil }
        self.keyCode = CGKeyCode(key)
        self.flags = flags
        self.display = shown.joined()
    }

    init(keyCode: Int, flags: CGEventFlags = []) {
        self.keyCode = CGKeyCode(keyCode)
        self.flags = flags
        self.display = ""
    }

    private static func glyph(for flag: CGEventFlags) -> String {
        switch flag {
        case .maskCommand:     "⌘"
        case .maskShift:       "⇧"
        case .maskAlternate:   "⌥"
        case .maskControl:     "⌃"
        case .maskSecondaryFn: "fn"
        default:               ""
        }
    }

    /// Posts the combination to whichever app is frontmost.
    func post() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
