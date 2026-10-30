import Foundation

struct ColorTemperatureTracker {
    var settleTime: TimeInterval = 1
    var settleTolerance = 150.0
    var smoothingFactor = 0.2
    var temperatureDeadband = 200.0
    var tintDeadband = 5.0

    private(set) var isCalibrated = false
    private(set) var room: WhiteBalance?
    private var anchor: (balance: WhiteBalance, since: Date)?
    private var offset = WhiteBalance(temperature: 0, tint: 0)
    private var smoothedGrayWorld: WhiteBalance?

    var roomBalance: WhiteBalance? { room ?? anchor?.balance }

    mutating func reset() {
        isCalibrated = false
        room = nil
        anchor = nil
        offset = WhiteBalance(temperature: 0, tint: 0)
        smoothedGrayWorld = nil
    }

    mutating func update(current: WhiteBalance?, grayWorld: WhiteBalance?,
                         isFaceVisible: Bool, at now: Date = .now) -> WhiteBalance? {
        guard isFaceVisible else {
            if !isCalibrated { anchor = nil }
            return nil
        }
        guard let grayWorld else { return nil }
        smoothedGrayWorld = smoothedGrayWorld.map {
            WhiteBalance(temperature: $0.temperature + smoothingFactor * (grayWorld.temperature - $0.temperature),
                         tint: $0.tint + smoothingFactor * (grayWorld.tint - $0.tint))
        } ?? grayWorld

        return isCalibrated ? track() : calibrate(current: current, now: now)
    }

    private mutating func calibrate(current: WhiteBalance?, now: Date) -> WhiteBalance? {
        guard let current, let smoothed = smoothedGrayWorld else { return nil }
        guard let anchor, abs(current.temperature - anchor.balance.temperature) <= settleTolerance else {
            anchor = (current, now)
            return nil
        }
        guard now.timeIntervalSince(anchor.since) >= settleTime else { return nil }

        offset = WhiteBalance(temperature: current.temperature - smoothed.temperature,
                              tint: current.tint - smoothed.tint)
        isCalibrated = true
        room = current
        return current
    }

    private mutating func track() -> WhiteBalance? {
        guard let smoothed = smoothedGrayWorld, let room else { return nil }
        let candidate = WhiteBalance(temperature: smoothed.temperature + offset.temperature,
                                     tint: smoothed.tint + offset.tint)
        guard abs(candidate.temperature - room.temperature) > temperatureDeadband
                || abs(candidate.tint - room.tint) > tintDeadband else { return nil }
        self.room = candidate
        return candidate
    }
}
