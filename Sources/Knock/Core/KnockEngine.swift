import AppKit
import Observation
import os

/// Ties the sensor, the detector and the action runner together, and publishes
/// the state the UI shows.
@MainActor
@Observable
final class KnockEngine {

    static let shared = KnockEngine()

    // MARK: published state

    enum Status: Equatable {
        case running
        case paused
        case noSensor(String)
        /// The sensor accepted `start()` but no samples are arriving. Treated as
        /// its own state because "start did not throw" is not evidence of data.
        case noData

        var label: String {
            switch self {
            case .running:           "検出中"
            case .paused:            "一時停止中"
            case .noSensor(let why): why
            case .noData:            "センサーからデータが届いていません"
            }
        }

        var isHealthy: Bool { self == .running }
    }

    private(set) var status: Status = .paused
    /// Latest high-passed energy, in g — drives the live meter.
    private(set) var energy: Double = 0
    /// Recent energy history for the waveform, newest last.
    private(set) var energyHistory: [Double] = Array(repeating: 0, count: 160)
    private(set) var lastGesture: KnockGesture?
    private(set) var lastGestureTime: Date?
    private(set) var lastOutcome: ActionRunner.Outcome?
    /// While the tuning pane is on screen, knocks are shown but no action runs.
    ///
    /// This used to be a plain flag set from `onAppear` / `onDisappear`. SwiftUI
    /// does not guarantee `onDisappear` when a tab changes or a window closes,
    /// so a missed call left the flag stuck on and silently swallowed every
    /// gesture. It is now a lease the visible view has to keep renewing.
    private var observationLease: Date = .distantPast
    var isObserving: Bool { observationLease > .now }
    private(set) var calibrationImpulses: [KnockImpulse] = []

    /// Guided left/right training.
    enum CalibrationPhase: Equatable { case idle, left, right }
    private(set) var calibrationPhase: CalibrationPhase = .idle
    private(set) var calibrationLeftSamples: [SIMD3<Double>] = []
    private(set) var calibrationRightSamples: [SIMD3<Double>] = []
    private(set) var calibrationResult: SideCalibration?

    /// Hardware presence, decided once at launch.
    let hasSensor: Bool

    /// Proof of life from the sensor, so the UI can tell "armed" from "silent".
    private(set) var sampleRateObserved: Double = 0
    private(set) var totalSamples: Int = 0
    private var samplesSinceCheck = 0
    private(set) var blockedByObservation = 0
    private(set) var actionsRun = 0
    var detectorDiagnostics: String { detector.diagnostics }
    private var lastSampleAt: Date?
    private var watchdog: Timer?

    // MARK: parts

    private let settings = Settings.shared
    private let detector = TapDetector()
    private let runner = ActionRunner()
    private let inputMonitor = InputActivityMonitor()
    private let source: MotionSource
    private let log = Logger(subsystem: "app.knock", category: "engine")
    private var energyTick = 0

    private init() {
        let supported = HIDAccelerometerSource.isSupported
        hasSensor = supported
        source = supported ? HIDAccelerometerSource() : SimulatedMotionSource()

        source.onSample = { [weak self] sample in
            guard let self else { return }
            totalSamples += 1
            samplesSinceCheck += 1
            lastSampleAt = .now
            detector.consume(sample)
        }
        detector.onEnergy = { [weak self] value in
            self?.recordEnergy(value)
        }
        detector.inputActivityProvider = { [weak self] in
            self?.inputMonitor.lastActivity ?? -.infinity
        }
        detector.onImpulse = { [weak self] impulse in
            self?.recordImpulse(impulse)
        }
        detector.onGesture = { [weak self] gesture in
            self?.handle(gesture)
        }
    }

    // MARK: lifecycle

    func start() {
        applySettings()
        inputMonitor.start()
        guard settings.isEnabled else {
            status = .paused
            return
        }
        do {
            try source.start(intervalMicroseconds: settings.reportInterval)
            detector.reset()
            status = .running
            startWatchdog()
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .noSensor(reason)
            log.error("start failed: \(reason, privacy: .public)")
        }
    }

    func stop() {
        source.stop()
        detector.reset()
        inputMonitor.stop()
        watchdog?.invalidate()
        watchdog = nil
        sampleRateObserved = 0
        status = .paused
    }

    /// Checks once a second that samples are still flowing.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSampleFlow() }
        }
    }

    private func checkSampleFlow() {
        sampleRateObserved = Double(samplesSinceCheck)
        samplesSinceCheck = 0

        guard settings.isEnabled else { return }
        let silent = lastSampleAt.map { Date.now.timeIntervalSince($0) > 2 } ?? true
        switch (silent, status) {
        case (true, .running):
            status = .noData
        case (false, .noData):
            status = .running
        default:
            break
        }
    }

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        if enabled { start() } else { stop() }
    }

    /// Re-reads every tuning value; called whenever a slider moves.
    func applySettings() {
        detector.sensitivity = settings.sensitivity
        detector.multiTapWindow = settings.multiTapWindow
        detector.invertSides = settings.invertSides
        detector.suppressDuringInput = settings.suppressDuringTyping
        detector.sideCalibration = settings.sideCalibration
    }

    /// The sample rate can only change by restarting the sensor.
    func restartSensor() {
        guard settings.isEnabled else { return }
        source.stop()
        start()
    }

    // MARK: detection

    private func recordEnergy(_ value: Double) {
        energy = value
        // The sensor runs at 100–400 Hz; the waveform only needs ~40 fps.
        energyTick += 1
        guard energyTick % 4 == 0 else { return }
        energyHistory.removeFirst()
        energyHistory.append(value)
    }

    private func handle(_ gesture: KnockGesture) {
        guard !isObserving else {
            blockedByObservation += 1
            lastGesture = gesture
            lastGestureTime = .now
            return
        }
        guard settings.isEnabled else { return }
        if isExcludedAppFrontmost() {
            log.info("skipped: frontmost app is excluded")
            return
        }

        let action = settings.bindings[gesture.side, gesture.count]
        lastGesture = gesture
        lastGestureTime = .now

        guard action.isConfigured else {
            if settings.showHUD {
                HUD.shared.show(title: "\(gesture.side.label) \(gesture.count)回",
                                detail: "割り当てがありません",
                                symbol: "minus.circle",
                                isFailure: false)
            }
            return
        }

        let outcome = runner.run(action)
        actionsRun += 1
        lastOutcome = outcome
        if settings.playSound {
            NSSound(named: outcome.isFailure ? "Funk" : "Pop")?.play()
        }
        if settings.showHUD {
            HUD.shared.show(title: outcome.title,
                            detail: outcome.detail ?? "\(gesture.side.label) · \(gesture.count)回",
                            symbol: outcome.symbol,
                            isFailure: outcome.isFailure)
        }
    }

    private func isExcludedAppFrontmost() -> Bool {
        guard let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return settings.excludedApps.contains(identifier)
    }

    // MARK: calibration & testing

    /// Called repeatedly by the tuning pane while it is visible. The lease
    /// lapses on its own if the view goes away without telling us.
    func renewObservation() {
        observationLease = .now.addingTimeInterval(2.5)
    }

    func endObservation() {
        observationLease = .distantPast
        calibrationPhase = .idle
        calibrationImpulses.removeAll()
    }

    private func recordImpulse(_ impulse: KnockImpulse) {
        switch calibrationPhase {
        case .left:
            calibrationLeftSamples.append(impulse.onset)
        case .right:
            calibrationRightSamples.append(impulse.onset)
        case .idle:
            break
        }
        guard isObserving else { return }
        calibrationImpulses.append(impulse)
        if calibrationImpulses.count > 12 { calibrationImpulses.removeFirst() }
    }

    // MARK: guided side calibration

    func startSideCalibration() {
        calibrationLeftSamples.removeAll()
        calibrationRightSamples.removeAll()
        calibrationResult = nil
        calibrationPhase = .left
        renewObservation()
    }

    func advanceSideCalibration() {
        switch calibrationPhase {
        case .left:
            calibrationPhase = .right
        case .right:
            calibrationPhase = .idle
            finishSideCalibration()
        case .idle:
            break
        }
    }

    func cancelSideCalibration() {
        calibrationPhase = .idle
        calibrationLeftSamples.removeAll()
        calibrationRightSamples.removeAll()
    }

    private func finishSideCalibration() {
        guard let trained = SideCalibration.train(left: calibrationLeftSamples,
                                                  right: calibrationRightSamples) else {
            calibrationResult = nil
            return
        }
        calibrationResult = trained
        settings.sideCalibration = trained
        applySettings()
    }

    /// Runs a binding from the UI, exactly as a knock would.
    func preview(_ action: KnockAction) {
        let outcome = runner.run(action)
        actionsRun += 1
        lastOutcome = outcome
        HUD.shared.show(title: outcome.title,
                        detail: outcome.detail ?? "テスト実行",
                        symbol: outcome.symbol,
                        isFailure: outcome.isFailure)
    }

    /// Feeds a synthetic knock through the whole pipeline; used when the machine
    /// has no readable sensor, and by the "試す" button.
    func simulate(side: KnockSide, count: Int) {
        if let simulated = source as? SimulatedMotionSource {
            for index in 0..<count {
                simulated.injectTap(side: side, after: Double(index) * 0.16)
            }
        } else {
            handle(KnockGesture(side: side, count: count))
        }
    }
}
