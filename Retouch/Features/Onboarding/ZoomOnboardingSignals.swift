//
//  ZoomOnboardingSignals.swift
//  Retouch
//

import Observation
import SwiftUI

@MainActor
@Observable
final class ZoomOnboardingSignals: OnboardingSignalSource {
    @ObservationIgnored var onSignal: ((OnboardingTrigger) -> Void)?
    private(set) var eyeAnchor: CGPoint? = ZoomOnboardingSignals.defaultEyeAnchor
    static let defaultEyeAnchor = CGPoint(x: 0.62, y: 0.38)
    private let zoomedInScale: CGFloat = 1.8

    @ObservationIgnored private let session: MirrorSession
    @ObservationIgnored private var listener: UUID?
    @ObservationIgnored private var didSendHandNearEye = false
    @ObservationIgnored private var didSendZoomedIn = false

    init(session: MirrorSession) {
        self.session = session
    }

    func connect() {
        guard listener == nil else { return }
        didSendHandNearEye = false
        didSendZoomedIn = false
        listener = session.addTrackingListener { [weak self] tracking, zoom in
            self?.handle(tracking, zoom)
        }
    }

    func disconnect() {
        if let listener { session.removeTrackingListener(listener) }
        listener = nil
    }

    private func handle(_ tracking: ZoomTracking, _ zoom: ZoomState) {
        if let eye = Self.normalized(tracking.face.rightEye ?? tracking.face.leftEye, in: tracking.viewSize) {
            eyeAnchor = eye
        }

        let onEye = tracking.target == .leftEye || tracking.target == .rightEye
        guard onEye else {
            didSendHandNearEye = false
            didSendZoomedIn = false
            return
        }
        if !didSendHandNearEye {
            didSendHandNearEye = true
            onSignal?(.handNearEye)
        }
        if !didSendZoomedIn, zoom.scale >= zoomedInScale {
            didSendZoomedIn = true
            onSignal?(.zoomedIn)
        }
    }

    private static func normalized(_ point: CGPoint?, in size: CGSize) -> CGPoint? {
        guard let point, size.width > 0, size.height > 0 else { return nil }
        return CGPoint(x: min(max(point.x / size.width, 0), 1),
                       y: min(max(point.y / size.height, 0), 1))
    }
}
