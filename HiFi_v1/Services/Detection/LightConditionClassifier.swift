import Foundation

/// Turns the smoothed room lux into a stable lighting condition (PRD Epic 2).
///
/// Two layers of stabilisation on top of the meter's smoothing, so a single
/// dark frame or a hand waved past the camera can't flip the condition
/// (Scenario 2.1.2):
///   1. Hysteresis: leaving a class needs the reading a little past the
///      boundary, so noise right at 300 or 750 lux can't toggle it.
///   2. Debounce: a new class must hold for `dwellTime` before it is committed.
struct LightConditionClassifier {
    struct Thresholds {
        var darkBelow = 300.0
        var brightAbove = 750.0
        /// Fraction past the boundary needed to leave a class (0.1 → leave dark above 330 lux).
        var hysteresis = 0.1
    }

    var thresholds = Thresholds()
    /// PRD: 0.5–1 s.
    var dwellTime: TimeInterval = 0.5

    /// Nil until the first reading has held for `dwellTime`.
    private(set) var condition: LightCondition?
    private var pending: (condition: LightCondition, since: Date)?

    mutating func reset() {
        condition = nil
        pending = nil
    }

    /// Returns true when the committed condition changed.
    @discardableResult
    mutating func ingest(_ lux: Double, at now: Date = .now) -> Bool {
        let candidate = classify(lux)
        guard candidate != condition else {
            pending = nil
            return false
        }
        if pending?.condition != candidate {
            pending = (candidate, now)
        }
        if let pending, now.timeIntervalSince(pending.since) >= dwellTime {
            condition = candidate
            self.pending = nil
            return true
        }
        return false
    }

    private func classify(_ lux: Double) -> LightCondition {
        let t = thresholds
        switch condition {
        case .dark? where lux <= t.darkBelow * (1 + t.hysteresis): return .dark
        case .bright? where lux >= t.brightAbove * (1 - t.hysteresis): return .bright
        default: break
        }
        if lux < t.darkBelow { return .dark }
        if lux > t.brightAbove { return .bright }
        return .medium
    }
}
