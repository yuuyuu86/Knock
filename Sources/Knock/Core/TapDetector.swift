import Foundation

enum KnockSide: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, right
    var id: String { rawValue }
    var label: String { self == .left ? "左側" : "右側" }
    var symbol: String { self == .left ? "arrow.left" : "arrow.right" }
    var flipped: KnockSide { self == .left ? .right : .left }
}

/// A finished gesture: which side was struck and how many times.
struct KnockGesture: Equatable {
    var side: KnockSide
    var count: Int
}

/// A single detected impulse, before it is grouped into a gesture.
struct KnockImpulse: Equatable {
    var side: KnockSide
    var strength: Double
    var time: TimeInterval
    /// Direction of the leading edge, normalised. This is what the side
    /// classifier is trained on.
    var onset: SIMD3<Double>
}

/// Turns a stream of accelerometer samples into knock gestures.
///
/// The pipeline is deliberately simple so it stays predictable on a machine
/// where the sensor also picks up typing, trackpad clicks and desk bumps:
///
/// 1. A one-pole high-pass removes gravity and slow tilting.
/// 2. The energy of the high-passed vector is compared against a threshold.
/// 3. An impulse must rise and fall quickly — a knock is a spike, a bump is not.
/// 4. The sign of the lateral axis during the onset decides left vs. right.
/// 5. Impulses that land inside the multi-tap window become one gesture.
final class TapDetector {

    // MARK: tuning

    /// 0…1, exposed to the user as the sensitivity slider.
    var sensitivity: Double = 0.5
    /// How long to keep waiting for another tap before emitting the gesture.
    var multiTapWindow: TimeInterval = 0.38
    /// Minimum gap between two impulses; blocks sensor ringing after a strike.
    var refractoryPeriod: TimeInterval = 0.085
    /// Swaps the side mapping after classification.
    var invertSides = false
    /// Learned left/right discriminant. Falls back to the lateral axis.
    var sideCalibration: SideCalibration = .uncalibrated
    /// Ignore impulses that arrive while the user is typing or clicking.
    var suppressDuringInput = true
    /// How long after a key press or click the detector stays muted.
    var inputSuppressionWindow: TimeInterval = 0.22

    // MARK: outputs

    var onGesture: ((KnockGesture) -> Void)?
    var onImpulse: ((KnockImpulse) -> Void)?
    /// Called for every sample with the high-passed energy — drives the live meter.
    var onEnergy: ((Double) -> Void)?

    // Stage counters. Cheap, and the only way to see where a knock is lost.
    private(set) var countOverGate = 0
    private(set) var countRejectedRefractory = 0
    private(set) var countRejectedInput = 0
    private(set) var countImpulses = 0
    private(set) var countGestures = 0
    private(set) var peakEnergySeen = 0.0
    private(set) var lastGateValue = 0.0

    /// Supplies the timestamp of the most recent keyboard/trackpad event.
    /// Wired to `InputActivityMonitor`; returns `-.infinity` when unset, which
    /// disables suppression rather than blocking everything.
    var inputActivityProvider: () -> TimeInterval = { -.infinity }

    // MARK: state

    private var lowPass = (x: 0.0, y: 0.0, z: 0.0)
    private var primed = false
    private var lastSampleTime: TimeInterval = 0

    private var lastImpulseTime: TimeInterval = -.infinity
    private var pendingSide: KnockSide?
    private var pendingCount = 0
    private var pendingTimer: DispatchSourceTimer?

    /// Rolling window of recent energy, used for the adaptive noise floor.
    private var noiseFloor = 0.0

    /// Onset bookkeeping: while an impulse is being measured we accumulate the
    /// lateral component so the side decision uses the whole leading edge.
    private var onsetSamplesLeft = 0
    private var onsetVector = SIMD3<Double>.zero
    private var onsetPeak = 0.0

    /// Maps the 0…1 slider onto a usable energy threshold, in g.
    /// Low sensitivity needs a firm knock; high sensitivity reacts to a light tap.
    private var threshold: Double {
        let high = 0.020   // light tap
        let low  = 0.130   // firm knock
        return low + (high - low) * max(0, min(1, sensitivity))
    }

    /// One line describing every stage, for the diagnostics readout.
    var diagnostics: String {
        String(format: "閾値%.3f 超過%d 不応期却下%d 入力却下%d 打撃%d ジェスチャ%d 最大%.3f",
               lastGateValue, countOverGate, countRejectedRefractory,
               countRejectedInput, countImpulses, countGestures, peakEnergySeen)
    }

    func resetCounters() {
        countOverGate = 0
        countRejectedRefractory = 0
        countRejectedInput = 0
        countImpulses = 0
        countGestures = 0
        peakEnergySeen = 0
    }

    func reset() {
        primed = false
        lowPass = (0, 0, 0)
        noiseFloor = 0
        cancelPending()
    }

    // MARK: sample intake

    func consume(_ sample: MotionSample) {
        guard primed else {
            lowPass = (sample.x, sample.y, sample.z)
            lastSampleTime = sample.time
            primed = true
            return
        }

        let dt = max(0.0005, min(0.05, sample.time - lastSampleTime))
        lastSampleTime = sample.time

        // One-pole low-pass ≈ 3 Hz corner; whatever it does not follow is the impulse.
        let alpha = dt / (dt + 1.0 / (2 * .pi * 3.0))
        lowPass.x += alpha * (sample.x - lowPass.x)
        lowPass.y += alpha * (sample.y - lowPass.y)
        lowPass.z += alpha * (sample.z - lowPass.z)

        let hx = sample.x - lowPass.x
        let hy = sample.y - lowPass.y
        let hz = sample.z - lowPass.z
        let energy = (hx * hx + hy * hy + hz * hz).squareRoot()

        // Track the quiet-time noise level so a humming desk raises the bar.
        noiseFloor += 0.002 * (energy - noiseFloor)
        onEnergy?(energy)

        if onsetSamplesLeft > 0 {
            onsetSamplesLeft -= 1
            onsetVector += SIMD3(hx, hy, hz)
            onsetPeak = max(onsetPeak, energy)
            if onsetSamplesLeft == 0 { finishOnset(at: sample.time) }
            return
        }

        let gate = max(threshold, noiseFloor * 4.5)
        lastGateValue = gate
        peakEnergySeen = max(peakEnergySeen, energy)
        guard energy > gate else { return }
        countOverGate += 1

        guard sample.time - lastImpulseTime > refractoryPeriod else {
            countRejectedRefractory += 1
            return
        }
        if suppressDuringInput, sample.time - inputActivityProvider() < inputSuppressionWindow {
            countRejectedInput += 1
            return
        }

        // Start measuring the leading edge — roughly 12 ms of samples.
        onsetSamplesLeft = max(2, Int(0.012 / dt))
        onsetVector = SIMD3(hx, hy, hz)
        onsetPeak = energy
    }

    private func finishOnset(at time: TimeInterval) {
        lastImpulseTime = time

        // Normalise so the direction, not the force of the knock, decides.
        let magnitude = (onsetVector * onsetVector).sum().squareRoot()
        let direction = magnitude > 1e-9 ? onsetVector / magnitude : SIMD3<Double>.zero

        var side = sideCalibration.side(for: direction)
        if invertSides { side = side.flipped }

        let impulse = KnockImpulse(side: side, strength: onsetPeak, time: time, onset: direction)
        countImpulses += 1
        onImpulse?(impulse)
        accumulate(impulse)
        onsetVector = .zero
        onsetPeak = 0
    }

    // MARK: multi-tap grouping

    private func accumulate(_ impulse: KnockImpulse) {
        if pendingSide == nil {
            pendingSide = impulse.side
            pendingCount = 1
        } else {
            // Taps on the far side mid-sequence are treated as part of the same
            // gesture; the first strike decides the side, which is what people
            // actually do when they knock quickly.
            pendingCount += 1
        }
        scheduleFlush()
    }

    private func scheduleFlush() {
        pendingTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + multiTapWindow)
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.resume()
        pendingTimer = timer
    }

    private func flush() {
        defer { cancelPending() }
        guard let side = pendingSide, pendingCount > 0 else { return }
        countGestures += 1
        onGesture?(KnockGesture(side: side, count: min(pendingCount, 3)))
    }

    private func cancelPending() {
        pendingTimer?.cancel()
        pendingTimer = nil
        pendingSide = nil
        pendingCount = 0
        onsetSamplesLeft = 0
    }
}
