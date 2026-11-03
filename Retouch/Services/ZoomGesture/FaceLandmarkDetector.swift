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
    private let noseGain = 0.55
    private let cheekGain = 0.6
    private let lock = NSLock()
    private var busy = false
    private var cache: FaceObservation?

    var latest: FaceObservation? {
        lock.lock()
        defer { lock.unlock() }
        return cache
    }
    
    func reset() {
        lock.lock()
        cache = nil
        lock.unlock()
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

        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height)
        }
        func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let pts = region?.normalizedPoints, !pts.isEmpty else { return nil }
            let sx = pts.reduce(0) { $0 + $1.x } / CGFloat(pts.count)
            let sy = pts.reduce(0) { $0 + $1.y } / CGFloat(pts.count)
            return point(CGPoint(x: sx, y: sy))
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

        // Vision tidak mengisi yaw di device ini, jadi sudut diperkirakan dari landmark
        var yaw = Double.nan
        if let l = leftEye, let r = rightEye {
            let contour = lm.faceContour?.normalizedPoints.map(point) ?? []
            yaw = estimateYaw(leftEye: l, rightEye: r, nose: center(lm.nose),
                              contour: contour, aspect: aspect)
        }

        return FaceObservation(
            leftEye: leftEye,
            rightEye: rightEye,
            lips: center(lm.outerLips).map { CGPoint(x: $0.x, y: $0.y - box.height * 0.06) },
            center: CGPoint(x: box.midX, y: box.midY),
            width: box.width,
            yaw: yaw,
            aspect: Double(box.height / (box.width * aspect))
        )
    }
    
    private func estimateYaw(leftEye l: CGPoint, rightEye r: CGPoint, nose: CGPoint?,
                             contour: [CGPoint], aspect: CGFloat) -> Double {
        func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        let le = iso(l), re = iso(r)
        let dist = hypot(re.x - le.x, re.y - le.y)
        guard dist > 0 else { return .nan }
        let ux = (re.x - le.x) / dist, uy = (re.y - le.y) / dist
        let mx = (le.x + re.x) / 2, my = (le.y + re.y) / 2
        func along(_ p: CGPoint) -> CGFloat {
            let q = iso(p)
            return (q.x - mx) * ux + (q.y - my) * uy
        }

        var angles: [Double] = []
        if let nose {
            angles.append(atan(Double(along(nose) / dist) / noseGain))
        }
        if contour.count >= 5 {
            let xs = contour.map(along)
            let right = xs.max() ?? 0
            let left = -(xs.min() ?? 0)
            if right > 0, left > 0 {
                angles.append(atan(Double((left - right) / (left + right)) / cheekGain))
            }
        }
        guard !angles.isEmpty else { return .nan }
        // Dua petunjuk saling bertentangan jauh: pembacaan tidak bisa dipercaya
        if angles.count == 2, abs(angles[0] - angles[1]) > 35 * .pi / 180 { return .nan }
        return angles.reduce(0, +) / Double(angles.count) * 180 / .pi
    }
}
