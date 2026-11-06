//
//  HandPointDetector.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//
import Vision
import QuartzCore

nonisolated final class HandPointDetector: @unchecked Sendable {
    private let pinchMax: CGFloat = 0.5          // jarak antar ujung jari / ukuran telapak
    private let minJointConfidence: Float = 0.25
    private let tipExtension: CGFloat = 0.4    // perpanjangan ke ujung brush, x ukuran telapak

    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private let queue = DispatchQueue(label: "zoom.hand")
    private let lock = NSLock()
    private var busy = false
    private var lastSubmit: CFTimeInterval = 0
    private var cache = HandScan()
    private var doneCount = 0
    private var windowStart = CACurrentMediaTime()
    private var rate = 0

    var latest: HandScan { lock.withLock { cache } }
    var detectionsPerSecond: Int { lock.withLock { rate } }

    /// Frame dilewati kalau proses sebelumnya belum selesai
    func submit(_ pixelBuffer: CVPixelBuffer) {
        let skip = lock.withLock { () -> Bool in
            let now = CACurrentMediaTime()
            if busy || now - lastSubmit < VisionBudget.interval { return true }
            busy = true
            lastSubmit = now
            return false
        }
        guard !skip else { return }

        let aspect = CGFloat(CVPixelBufferGetHeight(pixelBuffer)) / CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        nonisolated(unsafe) let buffer = pixelBuffer
        queue.async { [self] in
            let scan = detect(buffer, aspect: aspect)
            lock.withLock {
                cache = scan
                busy = false
                doneCount += 1
                let now = CACurrentMediaTime()
                if now - windowStart >= 1 {
                    rate = doneCount
                    doneCount = 0
                    windowStart = now
                }
            }
        }
    }

    private func detect(_ pixelBuffer: CVPixelBuffer, aspect: CGFloat) -> HandScan {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        try? handler.perform([request])
        var scan = HandScan()
        guard let results = request.results else { return scan }
        scan.handsSeen = results.count

        // Hitung di ruang yang sudah dikoreksi aspek, supaya jarak x dan y sebanding
        func scaled(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        func unscaled(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x / aspect, 0), 1), y: min(max(p.y, 0), 1))
        }
        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

        for obs in results {
            guard let thumb = try? obs.recognizedPoint(.thumbTip),
                  let index = try? obs.recognizedPoint(.indexTip),
                  let middle = try? obs.recognizedPoint(.middleTip),
                  let wrist = try? obs.recognizedPoint(.wrist),
                  let palm = try? obs.recognizedPoint(.middleMCP) else { continue }

            let tS = scaled(thumb.location)
            let iS = scaled(index.location)
            let mS = scaled(middle.location)
            let wS = scaled(wrist.location)
            let palmS = scaled(palm.location)

            let handSize = dist(wS, palmS)
            guard handSize > 0.01 else { continue }

            let pinch = max(dist(tS, iS), dist(tS, mS), dist(iS, mS)) / handSize
            let confidence = min(thumb.confidence, index.confidence, middle.confidence)

            if pinch < (scan.pinchRatio ?? .infinity) {
                scan.pinchRatio = pinch
                scan.confidence = confidence
            }

            guard confidence >= minJointConfidence, wrist.confidence > 0.2, palm.confidence > 0.2, pinch <= pinchMax else { continue }

            let g = CGPoint(x: (tS.x + iS.x + mS.x) / 3, y: (tS.y + iS.y + mS.y) / 3)

            var dx = g.x - wS.x
            var dy = g.y - wS.y
            let len = hypot(dx, dy)
            guard len > 0.001 else { continue }
            dx /= len
            dy /= len
            let tipS = CGPoint(x: g.x + dx * handSize * tipExtension,
                               y: g.y + dy * handSize * tipExtension)
            scan.grips.append(GripObservation(grip: unscaled(g), tip: unscaled(tipS)))
        }
        return scan
    }
}
