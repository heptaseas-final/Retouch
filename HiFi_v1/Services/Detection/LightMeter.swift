import Foundation

struct LightMeter {
    var calibrationConstant = 250.0
    var smoothingFactor = 0.3

    private(set) var smoothedLux: Double?
    private var smoothedLog: Double?

    mutating func reset() {
        smoothedLux = nil
        smoothedLog = nil
    }

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
