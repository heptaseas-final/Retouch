//
//  ZoomGestureServicing.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//
import AVFoundation

nonisolated protocol ZoomGestureServicing: AnyObject, Sendable {
    var onZoomChange: (@Sendable (ZoomState) -> Void)? { get set }
    func start()
    func stop()
    func setViewSize(_ size: CGSize)
    func process(_ pixelBuffer: CVPixelBuffer)
    func setGestureEnabled(_ isEnabled: Bool)
    func setManualTarget(_ target: ZoomTarget)
    func pinchChanged(_ magnification: CGFloat)
    func pinchEnded()
}
