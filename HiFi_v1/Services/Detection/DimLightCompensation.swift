import Foundation

/// How strongly to compensate for a dark room (PRD Epic 3), and how much light
/// the room gives on its own (PRD Epic 2, "excluding the screen's own light").
///
/// Compensation is proportional, as in SDD §4.5:
///
///     level = clamp((thresholdLux − roomLux) / thresholdLux, 0, 1)
///
/// It drives both the screen brightness and the edge light. Both light the
/// face and raise the measured lux. Read naively that looks like "the room got
/// brighter": compensation drops, the face goes dark again, and it loops.
/// To avoid that, the screen's contribution is measured once it has settled
/// and subtracted, giving an estimate of the room's light alone.
struct DimLightCompensation {
    enum State: Equatable {
        case off
        /// `baseLux`: room light just before compensation turned on.
        /// `contribution`: lux the brighter screen adds, known once settled.
        case on(baseLux: Double, since: Date, contribution: Double?)
    }

    /// Lux at and above which no compensation is needed; same as the dark threshold.
    var thresholdLux = 300.0
    /// Time for the screen to ramp up and camera exposure to settle before
    /// the screen's contribution is measured.
    var measureDelay: TimeInterval = 1.5
    /// Ignore level changes smaller than this, so the screen isn't nudged by sensor noise.
    var levelStep = 0.05
    /// Most light the screen can add to the face (a phone at ~30 cm, full
    /// white). Anything above this that shows up while measuring is the room
    /// getting brighter or exposure still settling, not the screen. Uncapped,
    /// it was counted as screen light forever, and compensation never turned off.
    var maxContributionLux = 100.0

    private(set) var state: State = .off
    /// 0 (off) to 1 (pitch dark).
    private(set) var level: Double = 0

    var isOn: Bool { state != .off }

    mutating func reset() {
        state = .off
        level = 0
    }

    /// Light of the room alone, with the screen's contribution taken out.
    func roomLux(from lux: Double) -> Double {
        switch state {
        case .off: lux
        case .on(let baseLux, _, nil): baseLux
        case .on(_, _, let contribution?): max(lux - contribution, 0)
        }
    }

    /// Feed the smoothed measured lux and whether the room is classified dark.
    /// Returns true when `level` changed.
    @discardableResult
    mutating func update(lux: Double, isDark: Bool, at now: Date = .now) -> Bool {
        let previous = level
        switch state {
        case .off:
            guard isDark else { return false }
            state = .on(baseLux: lux, since: now, contribution: nil)
            level = levelFor(lux)

        case .on where !isDark:
            reset()

        case .on(let baseLux, let since, nil):
            if now.timeIntervalSince(since) >= measureDelay {
                let contribution = min(max(lux - baseLux, 0), maxContributionLux)
                state = .on(baseLux: baseLux, since: since, contribution: contribution)
            }

        case .on:
            // Follow the room as it gets darker or lighter, without first
            // going back to baseline (Scenario 3.1.3).
            let target = levelFor(roomLux(from: lux))
            if abs(target - level) >= levelStep { level = target }
        }
        return level != previous
    }

    private func levelFor(_ lux: Double) -> Double {
        min(max((thresholdLux - lux) / thresholdLux, 0), 1)
    }
}
