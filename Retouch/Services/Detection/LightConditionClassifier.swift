import Foundation

struct LightConditionClassifier {
    struct Thresholds {
        var darkBelow = 20.0
        var brightAbove = 750.0
        var hysteresis = 0.1
    }

    var thresholds = Thresholds()
    var dwellTime: TimeInterval = 0.5

    private(set) var condition: LightCondition?
    private var pending: (condition: LightCondition, since: Date)?

    mutating func reset() {
        condition = nil
        pending = nil
    }

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
