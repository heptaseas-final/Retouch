//
//  HandPointDetector.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//
import Vision

nonisolated final class HandPointDetector: @unchecked Sendable {
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private let queue = DispatchQueue(label: "zoom.hand")
    private let lock = NSLock()
    private var busy = false
    private var cache: [CGPoint] = []

    var latest: [CGPoint] { lock.withLock { cache } }

    /// frame dilewati kalau proses sebelumnya belum selesai
    func submit(_ pixelBuffer: CVPixelBuffer) {
        let skip = lock.withLock { () -> Bool in
            if busy { return true }
            busy = true
            return false
        }
        guard !skip else { return }

        queue.async { [self] in
            let points = detect(pixelBuffer)
            lock.withLock {
                cache = points
                busy = false
            }
        }
    }

    private func detect(_ pixelBuffer: CVPixelBuffer) -> [CGPoint] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        try? handler.perform([request])
        guard let results = request.results else { return [] }

        var points: [CGPoint] = []
        for obs in results {
            guard let idx = try? obs.recognizedPoint(.indexTip), idx.confidence > 0.3 else { continue }
            if let thb = try? obs.recognizedPoint(.thumbTip), thb.confidence > 0.3 {
                points.append(CGPoint(x: (idx.location.x + thb.location.x) / 2,
                                      y: (idx.location.y + thb.location.y) / 2))
            } else {
                points.append(idx.location)
            }
        }
        return points
    }
}
