import Vision
import QuartzCore

/// Deteksi wajah (mata, bibir, dahi, perkiraan sudut kepala). Jalan async, frame dilewati kalau masih sibuk
/// atau belum waktunya (laju dibatasi lewat `minInterval`).
nonisolated final class FaceLandmarkDetector: @unchecked Sendable {
    private let request = VNDetectFaceLandmarksRequest()
    private let queue = DispatchQueue(label: "zoom.face")
    private let noseGain = 0.55
    private let cheekGain = 0.6
    private let lock = NSLock()
    private var busy = false
    private var gate = RateGate()
    private var cache: FaceObservation?
    private var cacheTime = Date.distantPast
    private var sequence = 0

    /// Hasil terakhir beserta nomor urut dan cap waktu. Nomor urut naik setiap ada hasil deteksi baru.
    var snapshot: DetectionSnapshot<FaceObservation?> {
        lock.lock()
        defer { lock.unlock() }
        return DetectionSnapshot(value: cache, sequence: sequence, timestamp: cacheTime)
    }

    var latest: FaceObservation? { snapshot.value }

    func reset() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    func submit(_ pixelBuffer: CVPixelBuffer, minInterval: TimeInterval = 0) {
        let mediaNow = CACurrentMediaTime()
        lock.lock()
        let skip = busy || !gate.allow(now: mediaNow, interval: minInterval)
        if !skip { busy = true }
        lock.unlock()
        guard !skip else { return }

        let stamp = Date()
        let aspect = CGFloat(CVPixelBufferGetHeight(pixelBuffer)) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        nonisolated(unsafe) let buffer = pixelBuffer
        queue.async { [self] in
            let handler = AnalysisImage.handler(for: buffer)
            try? handler.perform([request])
            let face = parse(aspect: aspect)
            lock.lock()
            cache = face
            cacheTime = stamp
            sequence += 1
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

        // Pitch (dongak) juga perkiraan dari landmark. NaN kalau landmark kurang atau kepala terlalu menoleh
        var pitch = Double.nan
        if ZoomTuning.pitchEnabled, let l = leftEye, let r = rightEye,
           !(yaw.isFinite && abs(yaw) > ZoomTuning.pitchMaxYaw) {
            pitch = estimatePitch(leftEye: l, rightEye: r, nose: center(lm.nose),
                                  mouth: center(lm.outerLips), aspect: aspect)
        }
        
        var mouth: (width: Double, height: Double, gap: Double)?
        if let l = leftEye, let r = rightEye {
            mouth = estimateMouth(leftEye: l, rightEye: r,
                                  outer: lm.outerLips?.normalizedPoints.map(point) ?? [],
                                  inner: lm.innerLips?.normalizedPoints.map(point) ?? [],
                                  aspect: aspect)
        }
        
        return FaceObservation(
            leftEye: leftEye,
            rightEye: rightEye,
            lips: center(lm.outerLips).map { CGPoint(x: $0.x, y: $0.y - box.height * 0.06) },
            center: CGPoint(x: box.midX, y: box.midY),
            width: box.width,
            yaw: yaw,
            aspect: Double(box.height / (box.width * aspect)),
            pitch: pitch,
            mouthWidth: mouth?.width ?? .nan,
            mouthHeight: mouth?.height ?? .nan,
            mouthGap: mouth?.gap ?? .nan
        )
    }

    /// Bentuk bibir dalam satuan jarak antar mata, searah garis mata (lebar) dan tegak lurusnya (tinggi),
    /// jadi ikut benar kalau kepala miring dan tidak terpengaruh jarak ke kamera.
    private func estimateMouth(leftEye l: CGPoint, rightEye r: CGPoint,
                               outer: [CGPoint], inner: [CGPoint],
                               aspect: CGFloat) -> (width: Double, height: Double, gap: Double)? {
        guard outer.count >= 4 else { return nil }
        func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        let le = iso(l), re = iso(r)
        let dist = hypot(re.x - le.x, re.y - le.y)
        guard dist > 0 else { return nil }
        let ux = (re.x - le.x) / dist, uy = (re.y - le.y) / dist
        let vx = uy, vy = -ux
        func span(_ pts: [CGPoint], _ ax: CGFloat, _ ay: CGFloat) -> Double {
            let vals = pts.map { iso($0).x * ax + iso($0).y * ay }
            guard let lo = vals.min(), let hi = vals.max() else { return 0 }
            return Double((hi - lo) / dist)
        }
        return (width: span(outer, ux, uy),
                height: span(outer, vx, vy),
                gap: inner.count >= 2 ? span(inner, vx, vy) : 0)
    }
    
    /// Hidung menonjol ke depan, jadi saat dagu naik ujung hidung terlihat bergeser ke arah mata.
    /// Diukur sebagai posisi hidung di antara garis mata dan bibir, searah sumbu "turun" wajah
    /// (tegak lurus garis mata, jadi ikut benar kalau kepala miring). Positif = mendongak.
    private func estimatePitch(leftEye l: CGPoint, rightEye r: CGPoint, nose: CGPoint?,
                               mouth: CGPoint?, aspect: CGFloat) -> Double {
        guard let nose, let mouth else { return .nan }
        func iso(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        let le = iso(l), re = iso(r)
        let dist = hypot(re.x - le.x, re.y - le.y)
        guard dist > 0 else { return .nan }
        let ux = (re.x - le.x) / dist, uy = (re.y - le.y) / dist
        let vx = uy, vy = -ux                       // arah turun (koordinat Vision: y naik)
        let mx = (le.x + re.x) / 2, my = (le.y + re.y) / 2
        func down(_ p: CGPoint) -> CGFloat {
            let q = iso(p)
            return (q.x - mx) * vx + (q.y - my) * vy
        }
        let noseDown = down(nose), mouthDown = down(mouth)
        guard mouthDown > dist * 0.4, noseDown > 0 else { return .nan }
        let ratio = Double(noseDown / mouthDown)
        return atan((ZoomTuning.pitchNominalRatio - ratio) / ZoomTuning.pitchNoseGain) * 180 / .pi
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
