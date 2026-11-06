//
//  FaceLandmarkDetector.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//
import Vision

/// Deteksi wajah (mata, bibir, dahi, perkiraan sudut kepala). Jalan async, frame dilewati kalau masih sibuk.
nonisolated final class FaceLandmarkDetector: @unchecked Sendable {
    private let request = VNDetectFaceLandmarksRequest()
    private let queue = DispatchQueue(label: "zoom.face")
    private let lock = NSLock()
    private var busy = false
    private var cache: FaceObservation?

    var latest: FaceObservation? {
        lock.lock()
        defer { lock.unlock() }
        return cache
    }

    func submit(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        let skip = busy
        if !skip { busy = true }
        lock.unlock()
        guard !skip else { return }

        let aspect = CGFloat(CVPixelBufferGetHeight(pixelBuffer)) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        nonisolated(unsafe) let buffer = pixelBuffer
        queue.async { [self] in
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .leftMirrored)
            try? handler.perform([request])
            let face = parse(aspect: aspect)
            lock.lock()
            cache = face
            busy = false
            lock.unlock()
        }
    }

    private func parse(aspect: CGFloat) -> FaceObservation? {
        guard let face = request.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height }),
              let lm = face.landmarks else { return nil }
        let box = face.boundingBox

        func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let pts = region?.normalizedPoints, !pts.isEmpty else { return nil }
            let sx = pts.reduce(0) { $0 + $1.x } / CGFloat(pts.count)
            let sy = pts.reduce(0) { $0 + $1.y } / CGFloat(pts.count)
            return CGPoint(x: box.minX + sx * box.width, y: box.minY + sy * box.height)
        }

        let eyes = [center(lm.leftEye), center(lm.rightEye)].compactMap { $0 }.sorted { $0.x < $1.x }
        var leftEye: CGPoint?
        var rightEye: CGPoint?
        if eyes.count == 2 {
            leftEye = eyes[0]
            rightEye = eyes[1]
        } else if let only = eyes.first {
            if only.x < box.midX { leftEye = only } else { rightEye = only }
        }

        var forehead: CGPoint?
        if let l = leftEye, let r = rightEye {
            let mid = CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
            forehead = CGPoint(x: mid.x, y: mid.y + (box.maxY - mid.y) * 0.5)
        }

        // Vision tidak mengisi yaw/pitch di device ini, jadi sudut diperkirakan dari landmark
        var yaw = 0.0
        var pitchRatio = Double.nan
        if let l = leftEye, let r = rightEye, let n = center(lm.nose) {
            let eyeDist = hypot((r.x - l.x) * aspect, r.y - l.y)
            if eyeDist > 0 {
                let mid = CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
                let yawRatio = Double((n.x - mid.x) * aspect / eyeDist)
                yaw = atan(yawRatio / 0.55) * 180 / .pi
                pitchRatio = Double((mid.y - n.y) / eyeDist)
            }
        }

        return FaceObservation(
            leftEye: leftEye,
            rightEye: rightEye,
            lips: center(lm.outerLips).map { CGPoint(x: $0.x, y: $0.y - box.height * 0.06) },
            forehead: forehead,
            center: CGPoint(x: box.midX, y: box.midY),
            width: box.width,
            yaw: yaw,
            pitchRatio: pitchRatio,
            aspect: Double(box.height / (box.width * aspect))
        )
    }
}
