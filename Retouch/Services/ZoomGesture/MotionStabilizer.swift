import CoreMotion
import Foundation
import CoreGraphics

nonisolated final class MotionStabilizer: @unchecked Sendable {
    private struct Sample {
        var t: TimeInterval
        var ax: Double   // sudut putaran sekitar sumbu x perangkat (miring maju/mundur), radian, sudah dibatasi pita
        var ay: Double   // sudut putaran sekitar sumbu y perangkat (putar kiri/kanan), radian, sudah dibatasi pita
    }

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "stabilizer.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    private let lock = NSLock()
    private var samples: [Sample] = []
    private var ax = 0.0, ay = 0.0   // hasil high-pass
    private var bx = 0.0, by = 0.0   // hasil high-pass + low-pass
    private var lastT: TimeInterval?

    // Keadaan tampilan (zoom dan ukuran view), diisi dari MirrorViewModel
    private let viewLock = NSLock()
    private var viewScale: CGFloat = 1
    private var viewPan: CGSize = .zero
    private var viewSize: CGSize = .zero

    private var debugLast: TimeInterval = 0

    // MARK: - Lifecycle
    func start() {
        guard ZoomTuning.stabEnabled, manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / ZoomTuning.stabSampleRate
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            self.ingest(m.timestamp, m.rotationRate.x, m.rotationRate.y)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        lock.lock()
        samples.removeAll()
        ax = 0; ay = 0
        bx = 0; by = 0
        lastT = nil
        lock.unlock()
    }

    // MARK: - Keadaan tampilan
    func setViewSize(_ size: CGSize) {
        viewLock.lock(); viewSize = size; viewLock.unlock()
    }

    func setZoom(scale: CGFloat, pan: CGSize) {
        viewLock.lock(); viewScale = scale; viewPan = pan; viewLock.unlock()
    }

    // MARK: - Sensor
    private func ingest(_ t: TimeInterval, _ wx: Double, _ wy: Double) {
        lock.lock(); defer { lock.unlock() }
        if let last = lastT {
            let dt = min(max(t - last, 0.0005), 0.05)
            let decay = exp(-dt / ZoomTuning.stabHighPassTau)
            ax = (ax + wx * dt) * decay   // integrasi bocor = high-pass pada sudut
            ay = (ay + wy * dt) * decay
            let lp = 1 - exp(-dt / ZoomTuning.stabLowPassTau)
            bx += (ax - bx) * lp
            by += (ay - by) * lp
        }
        lastT = t
        samples.append(Sample(t: t, ax: bx, ay: by))
        if samples.count > 128 { samples.removeFirst(samples.count - 128) }
    }

    private func angles(at time: TimeInterval) -> (x: Double, y: Double)? {
        lock.lock(); defer { lock.unlock() }
        guard let last = samples.last else { return nil }
        if time >= last.t { return (last.ax, last.ay) }
        guard samples.count > 1, time > samples[0].t else { return (samples[0].ax, samples[0].ay) }
        var i = samples.count - 1
        while i > 1 && samples[i - 1].t > time { i -= 1 }
        let a = samples[i - 1], b = samples[i]
        let f = (time - a.t) / max(b.t - a.t, 1e-6)
        return (a.ax + (b.ax - a.ax) * f, a.ay + (b.ay - a.ay) * f)
    }

    // MARK: - Koreksi untuk renderer
    func drawableShift(drawableWidth: CGFloat) -> CGSize {
        viewLock.lock()
        let scale = viewScale, pan = viewPan, size = viewSize
        viewLock.unlock()
        guard size.width > 0, drawableWidth > 0 else { return .zero }

        let c = correction(scale: scale, pan: pan, viewSize: size)   // point layar, sudah dikali zoom
        let toPixels = drawableWidth / size.width
        return CGSize(width: c.width * toPixels, height: c.height * toPixels)
    }

    /// Offset koreksi dalam point layar (sesudah zoom).
    func correction(scale: CGFloat, pan: CGSize, viewSize: CGSize) -> CGSize {
        guard ZoomTuning.stabEnabled, scale > 1.001, viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let now = ProcessInfo.processInfo.systemUptime   // basis waktu sama dengan CMDeviceMotion.timestamp

        // Waktu acuan dan point layar per radian putaran
        var lookup = now - ZoomTuning.stabDelay
        var pointsPerRadian = Double(viewSize.width) / (2 * tan(ZoomTuning.stabVisibleFOVDegrees * .pi / 360))
        let frame = FrameClock.shared.latest(now: now)
        if let frame {
            lookup = frame.time + ZoomTuning.stabFrameBias
            if frame.hFOVDegrees > 1 {
                let long = max(frame.bufferWidth, frame.bufferHeight)
                let short = min(frame.bufferWidth, frame.bufferHeight)
                let focalPixels = (long / 2) / tan(frame.hFOVDegrees * .pi / 360)           // piksel kamera per radian
                let fill = max(Double(viewSize.width) / short, Double(viewSize.height) / long) // point layar per piksel kamera (aspect-fill)
                pointsPerRadian = focalPixels * fill
            }
        }

        #if DEBUG
        if now - debugLast > 1 {
            debugLast = now
            print("[Stab] frameClock=\(frame != nil) lag=\(Int((now - lookup) * 1000))ms scale=\(scale)")
        }
        #endif

        guard let a = angles(at: lookup) else { return .zero }

        // Zoom memperbesar goyangan, jadi koreksi dikali skala
        let k = pointsPerRadian * ZoomTuning.stabGain * Double(scale)

        // Tampilan di-mirror (lihat MirrorRenderer.uprightMirror). HP diputar ke kanan (sumbu y positif):
        // isi gambar bergeser ke kiri layar, jadi koreksinya ke kanan. HP miring (sumbu x positif):
        // isi gambar naik, jadi koreksinya turun.
        var dx = a.y * k
        var dy = a.x * k
        if ZoomTuning.stabInvertX { dx = -dx }
        if ZoomTuning.stabInvertY { dy = -dy }
        if !ZoomTuning.stabEnableX { dx = 0 }
        if !ZoomTuning.stabEnableY { dy = 0 }

        // Sisa ruang di tepi gambar setelah geser zoom (pan) dipakai
        let marginX = (scale - 1) * viewSize.width / 2 - abs(pan.width)
        let marginY = (scale - 1) * viewSize.height / 2 - abs(pan.height)
        return CGSize(width: softClamp(dx, marginX), height: softClamp(dy, marginY))
    }

    /// Membatasi dengan mulus: kecil = hampir linear, besar = menjenuh di batas ruang.
    private func softClamp(_ value: Double, _ margin: CGFloat) -> CGFloat {
        let m = Double(max(margin, 0)) * ZoomTuning.stabMarginUse
        guard m > 0.5 else { return 0 }
        return CGFloat(m * tanh(value / m))
    }
}
