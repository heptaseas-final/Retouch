import Foundation

/// Estimates room illuminance from the camera's auto exposure (PRD Epic 2, SDD §4.2).
///
/// Incident-light meter equation, N² / t = E · S / C, solved for E:
///
///     lux ≈ C · N² / (t · S)
///
/// N = f-number, t = exposure time in seconds, S = ISO, C = `calibrationConstant`.
/// When auto exposure runs out of range (a dark room with the frame rate held
/// at 30 fps), the image ends up darker than auto exposure wanted;
/// `exposureTargetOffset` says by how many EV, and is folded in.
///
/// The camera meters the face rather than the room, so this is an estimate
/// that is consistent enough for dark/medium/bright, not a calibrated lux
/// meter (PRD Scope, out of scope for v1).
struct LightMeter {
    /// C in the equation above. Typical incident meters use 250; tune it
    /// against a reference lux meter (SDD §9).
    var calibrationConstant = 250.0
    /// EMA weight of each new sample, applied in log space because lux spans
    /// orders of magnitude. At 10 samples/s, 0.3 ≈ 0.3 s time constant: fast
    /// enough to follow a light switch, slow enough to ignore single-frame noise.
    var smoothingFactor = 0.3

    private(set) var smoothedLux: Double?
    private var smoothedLog: Double?

    mutating func reset() {
        smoothedLux = nil
        smoothedLog = nil
    }

    /// Feeds one sample and returns the smoothed lux, or nil if the exposure
    /// values are unusable.
    mutating func ingest(_ sample: LightSample) -> Double? {
        guard let lux = Self.lux(sample, calibrationConstant: calibrationConstant), lux > 0 else { return smoothedLux }
        let log = log2(lux)
        let smoothed = smoothedLog.map { $0 + smoothingFactor * (log - $0) } ?? log
        smoothedLog = smoothed
        smoothedLux = pow(2, smoothed)
        return smoothedLux
    }

    static func lux(_ sample: LightSample, calibrationConstant: Double) -> Double? {
        guard sample.iso > 0, sample.exposureDuration > 0, sample.aperture > 0 else { return nil }
        let n2 = sample.aperture * sample.aperture
        return calibrationConstant * n2 / (sample.exposureDuration * sample.iso) * pow(2, sample.exposureTargetOffset)
    }
}
