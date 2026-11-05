import Foundation

nonisolated final class FrameClock: @unchecked Sendable {
    static let shared = FrameClock()

    struct Frame {
        var time: TimeInterval        // cap waktu pengambilan frame
        var bufferWidth: Double       // ukuran buffer kamera (piksel)
        var bufferHeight: Double
        var hFOVDegrees: Double       // sudut pandang horizontal format kamera yang aktif (sisi panjang buffer)
    }

    private let lock = NSLock()
    private var frame: Frame?
    private var receivedAt: TimeInterval = 0

    /// Dipanggil sekali per frame dari callback kamera.
    func note(frameTime: TimeInterval, bufferWidth: Double, bufferHeight: Double, hFOVDegrees: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock(); defer { lock.unlock() }
        // Kalau jam frame ternyata tidak sebasis dengan jam sensor, jangan dipakai (peredam jatuh ke mode cadangan)
        guard abs(now - frameTime) < 1.0 else {
            frame = nil
            return
        }
        frame = Frame(time: frameTime, bufferWidth: bufferWidth, bufferHeight: bufferHeight,
                      hFOVDegrees: hFOVDegrees)
        receivedAt = now
    }

    /// Frame terbaru, atau nil kalau belum ada atau sudah basi (kamera berhenti).
    func latest(now: TimeInterval) -> Frame? {
        lock.lock(); defer { lock.unlock() }
        guard let frame, now - receivedAt < 0.25 else { return nil }
        return frame
    }
}
