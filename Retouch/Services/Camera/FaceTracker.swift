import CoreImage
import QuartzCore
import Vision

final class FaceTracker {
    var memory: CFTimeInterval = 1.0
    var visibilityMemory: CFTimeInterval = 0.3

    var analysisWidth: CGFloat = 360

    private let queue = DispatchQueue(label: "autolight.face", qos: .userInitiated)
    private let lock = NSLock()
    private var isBusy = false
    private var lastFace: (rect: CGRect, seen: CFTimeInterval)?

    var face: CGRect? {
        lock.withLock {
            guard let lastFace, CACurrentMediaTime() - lastFace.seen < memory else { return nil }
            return lastFace.rect
        }
    }

    var isFaceVisible: Bool {
        lock.withLock {
            guard let lastFace else { return false }
            return CACurrentMediaTime() - lastFace.seen < visibilityMemory
        }
    }

    func reset() {
        lock.withLock { lastFace = nil }
    }

    func submit(_ image: CIImage) {
        let skip = lock.withLock { () -> Bool in
            if isBusy { return true }
            isBusy = true
            return false
        }
        guard !skip else { return }

        let scale = analysisWidth / image.extent.width
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        queue.async {
            let request = VNDetectFaceRectanglesRequest()
            try? VNImageRequestHandler(ciImage: small, options: [:]).perform([request])
            let largest = request.results?.max { $0.boundingBox.area < $1.boundingBox.area }
            self.lock.withLock {
                if let largest { self.lastFace = (largest.boundingBox, CACurrentMediaTime()) }
                self.isBusy = false
            }
        }
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
