import Foundation
import Observation
import ServiceManagement

/// The six slots, persisted as one blob in `UserDefaults`.
struct KnockBindings: Codable, Equatable, Sendable {
    /// Index 0 = single tap, 1 = double, 2 = triple.
    var left: [KnockAction]
    var right: [KnockAction]

    static let `default` = KnockBindings(
        left: [
            KnockAction(kind: .toggleMute),
            KnockAction(kind: .screenshotToClipboard),
            KnockAction(kind: .missionControl),
        ],
        right: [
            KnockAction(kind: .playPause),
            KnockAction(kind: .nextTrack),
            KnockAction(kind: .toggleWiFi),
        ])

    subscript(side: KnockSide, count: Int) -> KnockAction {
        get {
            let index = max(1, min(3, count)) - 1
            return side == .left ? left[index] : right[index]
        }
        set {
            let index = max(1, min(3, count)) - 1
            if side == .left { left[index] = newValue } else { right[index] = newValue }
        }
    }
}

/// User-facing configuration. Everything is written straight back to
/// `UserDefaults` so a crash never loses a binding.
@MainActor
@Observable
final class Settings {

    static let shared = Settings()

    // MARK: stored

    var isEnabled: Bool { didSet { store(isEnabled, "isEnabled") } }
    var bindings: KnockBindings { didSet { storeJSON(bindings, "bindings") } }
    /// 0…1; higher means a lighter tap is enough.
    var sensitivity: Double { didSet { store(sensitivity, "sensitivity") } }
    /// Seconds allowed between taps of one gesture.
    var multiTapWindow: Double { didSet { store(multiTapWindow, "multiTapWindow") } }
    var invertSides: Bool { didSet { store(invertSides, "invertSides") } }
    /// Learned left/right discriminant, from the guided calibration.
    var sideCalibration: SideCalibration { didSet { storeJSON(sideCalibration, "sideCalibration") } }
    var suppressDuringTyping: Bool { didSet { store(suppressDuringTyping, "suppressDuringTyping") } }
    var showHUD: Bool { didSet { store(showHUD, "showHUD") } }
    var playSound: Bool { didSet { store(playSound, "playSound") } }
    /// Sample rate in Hz; higher resolves fast triple taps better.
    var sampleRate: Int { didSet { store(sampleRate, "sampleRate") } }
    /// Bundle identifiers where Knock stays quiet.
    var excludedApps: [String] { didSet { store(excludedApps, "excludedApps") } }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }

    // MARK: init

    private let defaults = UserDefaults.standard

    private init() {
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
        }
        func number(_ key: String, _ fallback: Double) -> Double {
            UserDefaults.standard.object(forKey: key) as? Double ?? fallback
        }

        isEnabled = bool("isEnabled", true)
        sensitivity = number("sensitivity", 0.5)
        multiTapWindow = number("multiTapWindow", 0.38)
        invertSides = bool("invertSides", false)
        suppressDuringTyping = bool("suppressDuringTyping", true)
        showHUD = bool("showHUD", true)
        playSound = bool("playSound", false)
        sampleRate = UserDefaults.standard.object(forKey: "sampleRate") as? Int ?? 200
        excludedApps = UserDefaults.standard.stringArray(forKey: "excludedApps") ?? []
        launchAtLogin = SMAppService.mainApp.status == .enabled

        if let data = UserDefaults.standard.data(forKey: "sideCalibration"),
           let decoded = try? JSONDecoder().decode(SideCalibration.self, from: data) {
            sideCalibration = decoded
        } else {
            sideCalibration = .uncalibrated
        }

        if let data = UserDefaults.standard.data(forKey: "bindings"),
           let decoded = try? JSONDecoder().decode(KnockBindings.self, from: data) {
            bindings = decoded
        } else {
            bindings = .default
        }
    }

    // MARK: actions

    func resetBindings() {
        bindings = .default
    }

    func resetTuning() {
        sideCalibration = .uncalibrated
        sensitivity = 0.5
        multiTapWindow = 0.38
        invertSides = false
        suppressDuringTyping = true
        sampleRate = 200
    }

    /// Microseconds between samples, as the sensor wants it.
    var reportInterval: Int { max(1, 1_000_000 / max(20, sampleRate)) }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Unsigned builds cannot register a login item; reflect reality in the UI.
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    var launchAtLoginError: String?

    // MARK: persistence

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    private func storeJSON<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
