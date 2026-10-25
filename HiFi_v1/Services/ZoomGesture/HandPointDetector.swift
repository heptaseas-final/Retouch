//
//  HandPointDetector.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import Vision

/// titik tangan, tengah ujung jempol dan telunjuk (seperti memegang brush).
nonisolated final class HandPointDetector: @unchecked Sendable {
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()

    func detect(in pixelBuffer: CVPixelBuffer) -> [CGPoint] {
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
