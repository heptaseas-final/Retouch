import Foundation

/// Estimates the room light's colour temperature and decides when the camera
/// white balance should move (PRD Epic 4, SDD §4.3).
///
/// Holding a locked white balance and then releasing it to auto made skin
/// colour snap when the room light changed. Instead, WB stays under our
/// control and moves continuously:
///
///   1. calibrating: the camera's own (face-aware) auto WB finds the room's
///      light. Once it has been steady for `settleTime`, we note how far it
///      sits from the gray-world estimate (mostly the bias of a face filling
///      the frame) and take over.
///   2. tracking: the gray-world estimate keeps updating while WB is locked.
///      Its slow average plus the calibration offset is the room estimate.
///      It becomes the new target only when it moves past a deadband, so
///      small Kelvin changes are ignored (Scenario 4.1.2).
///
/// While the face isn't visible (a hand or brush in front of it), nothing is
/// fed in at all, so the colour stays put until the face is back (Scenario 4.1.3).
struct ColorTemperatureTracker {
    var settleTime: TimeInterval = 1
    var settleTolerance = 150.0
    /// EMA weight per sample of the gray-world estimate. At 10 samples/s, 0.2 ≈ 0.45 s time constant.
    var smoothingFactor = 0.2
    /// "Significant shift" for Epic 4 (SDD §9: to confirm with testing).
    var temperatureDeadband = 200.0
    var tintDeadband = 5.0

    private(set) var isCalibrated = false
    /// Room light as last committed; the camera glides to this.
    private(set) var room: WhiteBalance?
    private var anchor: (balance: WhiteBalance, since: Date)?
    private var offset = WhiteBalance(temperature: 0, tint: 0)
    private var smoothedGrayWorld: WhiteBalance?

    /// Room light as currently judged, during calibration too.
    var roomBalance: WhiteBalance? { room ?? anchor?.balance }

    mutating func reset() {
        isCalibrated = false
        room = nil
        anchor = nil
        offset = WhiteBalance(temperature: 0, tint: 0)
        smoothedGrayWorld = nil
    }

    /// Returns the new room light when the camera should glide to it.
    mutating func update(current: WhiteBalance?, grayWorld: WhiteBalance?,
                         isFaceVisible: Bool, at now: Date = .now) -> WhiteBalance? {
        guard isFaceVisible else {
            // Calibration must see the face for the whole settle time.
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
