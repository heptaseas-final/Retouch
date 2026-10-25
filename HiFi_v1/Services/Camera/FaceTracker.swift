import CoreImage
import QuartzCore
import Vision

/// Finds the face in the mirror image (SDD §4.4), so the edge light can be
/// kept off it and colour updates can pause while a hand or brush covers it.
///
/// Detection runs on its own queue and simply skips frames while busy, so it
/// never holds up the mirror. Frames are analysed in memory only.
final class FaceTracker {
    /// How long a face is remembered after it was last seen, so the clear
    /// area doesn't jump around when detection misses a frame.
    var memory: CFTimeInterval = 1.0
    /// How long after the last sighting the face still counts as visible.
    /// Shorter than `memory`, so an occluding hand is noticed quickly.
    var visibilityMemory: CFTimeInterval = 0.3
    /// Width frames are scaled to before detection; plenty for one large face.
    var analysisWidth: CGFloat = 360

    private let queue = DispatchQueue(label: "autolight.face", qos: .userInitiated)
    private let lock = NSLock()
    private var isBusy = false
    private var lastFace: (rect: CGRect, seen: CFTimeInterval)?

    /// Largest face in the last analysed image, as a normalised rect
    /// (0…1, origin bottom-left, like Core Image). Nil when none was seen recently.
    var face: CGRect? {
        lock.withLock {
            guard let lastFace, CACurrentMediaTime() - lastFace.seen < memory else { return nil }
            return lastFace.rect
        }
    }

    /// False while no face has been found for `visibilityMemory`, e.g. a hand covers it.
    var isFaceVisible: Bool {
        lock.withLock {
            guard let lastFace else { return false }
            return CACurrentMediaTime() - lastFace.seen < visibilityMemory
        }
    }

    /// Forgets the last face, e.g. after the camera reconnects.
    func reset() {
        lock.withLock { lastFace = nil }
    }

    /// Queues `image` for detection unless a detection is already running.
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
