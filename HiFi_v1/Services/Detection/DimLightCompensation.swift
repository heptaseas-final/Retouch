import Foundation

struct DimLightCompensation {
    enum State: Equatable {
        case off
        case on(baseLux: Double, since: Date, contribution: Double?)
    }

    var thresholdLux = 300.0

    var measureDelay: TimeInterval = 1.5
    var levelStep = 0.05
    var maxContributionLux = 100.0

    private(set) var state: State = .off
    private(set) var level: Double = 0

    var isOn: Bool { state != .off }

    mutating func reset() {
        state = .off
        level = 0
    }

    func roomLux(from lux: Double) -> Double {
        switch state {
        case .off: lux
        case .on(let baseLux, _, nil): baseLux
        case .on(_, _, let contribution?): max(lux - contribution, 0)
        }
    }

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
            // Follow the room as it gets darker or lighter.
            let target = levelFor(roomLux(from: lux))
            if abs(target - level) >= levelStep { level = target }
        }
        return level != previous
    }

    private func levelFor(_ lux: Double) -> Double {
        min(max((thresholdLux - lux) / thresholdLux, 0), 1)
    }
}
