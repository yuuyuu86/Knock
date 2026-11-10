import Foundation

/// Decides which side of the chassis was struck.
///
/// The first implementation assumed the lateral (`x`) axis would dominate a
/// knock. Measurements on real hardware said otherwise — across 45 recorded
/// taps, `x` was the largest component only 5 times. The vibration reaches the
/// sensor through the whole chassis, so the useful signal is the *direction* of
/// the onset vector, not any single axis.
///
/// So instead of assuming a geometry, learn one: record a handful of taps per
/// side, take the mean onset vector of each, and separate them with the
/// difference of those means. Classification is then a dot product.
struct SideCalibration: Codable, Equatable, Sendable {

    /// Direction that points from "right tap" toward "left tap".
    var weights: SIMD3<Double>
    /// Midpoint between the two class means, projected onto `weights`.
    var bias: Double
    /// How far apart the two classes sit, in units of their own spread.
    /// Below ~1.0 the calibration is not worth trusting.
    var separation: Double
    var sampleCount: Int

    var isCalibrated: Bool { sampleCount > 0 && separation > 0 }

    /// Falls back to the lateral axis, which is the best guess with no data.
    static let uncalibrated = SideCalibration(weights: SIMD3(1, 0, 0),
                                              bias: 0,
                                              separation: 0,
                                              sampleCount: 0)

    var quality: String {
        switch separation {
        case ..<0.8:  "判別が不安定です。もう一度お試しください"
        case ..<1.5:  "判別できますが、やや不安定です"
        case ..<3.0:  "良好です"
        default:      "非常に良好です"
        }
    }

    func side(for onset: SIMD3<Double>) -> KnockSide {
        (onset * weights).sum() - bias >= 0 ? .left : .right
    }

    /// Builds a discriminant from labelled onset vectors.
    /// Returns nil when either side has too few samples to mean anything.
    static func train(left: [SIMD3<Double>], right: [SIMD3<Double>]) -> SideCalibration? {
        guard left.count >= 3, right.count >= 3 else { return nil }

        func mean(_ values: [SIMD3<Double>]) -> SIMD3<Double> {
            values.reduce(SIMD3<Double>.zero, +) / Double(values.count)
        }
        let leftMean = mean(left)
        let rightMean = mean(right)

        var weights = leftMean - rightMean
        let magnitude = (weights * weights).sum().squareRoot()
        guard magnitude > 1e-9 else { return nil }
        weights /= magnitude

        // Project every sample and check the two clouds actually separate.
        let leftScores = left.map { ($0 * weights).sum() }
        let rightScores = right.map { ($0 * weights).sum() }

        func stats(_ scores: [Double]) -> (mean: Double, deviation: Double) {
            let mean = scores.reduce(0, +) / Double(scores.count)
            let variance = scores.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(scores.count)
            return (mean, variance.squareRoot())
        }
        let leftStats = stats(leftScores)
        let rightStats = stats(rightScores)
        let spread = max(1e-9, (leftStats.deviation + rightStats.deviation) / 2)
        let separation = abs(leftStats.mean - rightStats.mean) / spread

        return SideCalibration(weights: weights,
                               bias: (leftStats.mean + rightStats.mean) / 2,
                               separation: separation,
                               sampleCount: left.count + right.count)
    }
}
