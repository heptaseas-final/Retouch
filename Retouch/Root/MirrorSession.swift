//
//  MirrorSession.swift
//  Retouch
//

import Observation
import SwiftUI

@MainActor
@Observable
final class MirrorSession {
    typealias TrackingListener = @MainActor (ZoomTracking, ZoomState) -> Void

    let detector: AutoLightDetector
    let lighting: LightingViewModel
    @ObservationIgnored let stabilizer = MotionStabilizer()
    @ObservationIgnored let zoomGesture: ZoomGestureServicing

    private(set) var zoomState = ZoomState()
    private(set) var tracking = ZoomTracking()
    private(set) var debugInfo = ZoomDebugInfo()

    @ObservationIgnored private var listeners: [UUID: TrackingListener] = [:]

    init(zoomGesture: ZoomGestureServicing = ZoomGestureService()) {
        let detector = AutoLightDetector()
        self.detector = detector
        self.lighting = LightingViewModel(detector: detector)
        self.zoomGesture = zoomGesture

        detector.renderer.frameShift = { [stabilizer] (width: CGFloat) -> CGSize in
            stabilizer.drawableShift(drawableWidth: width)
        }
        zoomGesture.onZoomChange = { [weak self, stabilizer] state in
            stabilizer.setZoom(scale: state.scale, pan: state.offset)
            Task { @MainActor in self?.updateZoom(state) }
        }
        zoomGesture.onTracking = { [weak self] tracking in
            Task { @MainActor in self?.updateTracking(tracking) }
        }
        zoomGesture.onDebugInfo = { [weak self] info in
            Task { @MainActor in self?.debugInfo = info }
        }
        detector.frameForwarder.setHandler { [zoomGesture] buffer in
            zoomGesture.process(buffer)
        }
    }

    func start() {
        detector.start()
        zoomGesture.start()
        stabilizer.start()
    }

    func stop() {
        lighting.setAuto(true)
        detector.stop()
        zoomGesture.stop()
        stabilizer.stop()
    }

    func resetToDefaults() {
        zoomGesture.setGestureEnabled(true)
        lighting.setAuto(true)
    }

    func select(_ part: FacePart) {
        guard let target = part.zoomTarget else {
            zoomGesture.setGestureEnabled(true)
            return
        }
        zoomGesture.setGestureEnabled(false)
        zoomGesture.setManualTarget(target)
    }

    func setLightMode(_ mode: LightMode) {
        guard let color = mode.lightColor else {
            lighting.setAuto(true)
            return
        }
        lighting.select(color)
        lighting.setBrightness(1)
    }

    @discardableResult
    func addTrackingListener(_ listener: @escaping TrackingListener) -> UUID {
        let id = UUID()
        listeners[id] = listener
        return id
    }

    func removeTrackingListener(_ id: UUID) {
        listeners[id] = nil
    }

    private func updateZoom(_ state: ZoomState) {
        zoomState = state
        notify()
    }

    private func updateTracking(_ value: ZoomTracking) {
        tracking = value
        notify()
    }

    private func notify() {
        for listener in listeners.values { listener(tracking, zoomState) }
    }
}

extension FacePart {
    var zoomTarget: ZoomTarget? {
        switch self {
        case .face: nil
        case .leftEye: .leftEye
        case .rightEye: .rightEye
        case .mouth, .smile: .lips
        case .nose: .fullFace
        }
    }
}
