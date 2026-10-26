//
//  ZoomAnimator.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//

import SwiftUI

nonisolated final class ZoomAnimator: NSObject, @unchecked Sendable {
    var onChange: (@Sendable (ZoomState) -> Void)?

    private let zoomInTau: CGFloat = 0.14
    private let zoomOutTau: CGFloat = 0.20
    private let panTau: CGFloat = 0.12
    private let safeMargin: CGFloat = 0.25   // titik fokus dijaga minimal 25% dari tepi layar

    private var viewSize: CGSize = .zero
    private var goalScale: CGFloat = 1
    private var focus: CGPoint?
    private var currentScale: CGFloat = 1
    private var panX: CGFloat = 0
    private var panY: CGFloat = 0
    private var lastState = ZoomState()
    private var link: CADisplayLink?

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func setViewSize(_ size: CGSize) { viewSize = size }

    func setGoal(scale: CGFloat, focus: CGPoint?) {
        goalScale = scale
        self.focus = focus
    }

    @objc private func tick(_ link: CADisplayLink) {
        let size = viewSize
        guard size.width > 0, size.height > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dt = min(max(CGFloat(link.targetTimestamp - link.timestamp), 1.0 / 120.0), 0.05)

        let tau = goalScale > currentScale ? zoomInTau : zoomOutTau
        currentScale += (goalScale - currentScale) * (1 - exp(-dt / tau))

        // Geser seperlunya: hanya sejauh yang dibutuhkan supaya titik fokus tetap di zona aman
        let maxX = (currentScale - 1) * size.width / 2
        let maxY = (currentScale - 1) * size.height / 2
        var goalX: CGFloat = 0
        var goalY: CGFloat = 0
        if goalScale > 1, let f = focus {
            let ex = center.x + currentScale * (f.x - center.x)
            let ey = center.y + currentScale * (f.y - center.y)
            let wantX = center.x - ex
            let wantY = center.y - ey
            goalX = abs(wantX - panX) < size.width * 0.015 ? panX : wantX
            goalY = abs(wantY - panY) < size.height * 0.015 ? panY : wantY
        }
        
        goalX = min(max(goalX, -maxX), maxX)
        goalY = min(max(goalY, -maxY), maxY)

        let ap = 1 - exp(-dt / panTau)
        panX += (goalX - panX) * ap
        panY += (goalY - panY) * ap

        if abs(lastState.scale - currentScale) > 0.0005
            || abs(lastState.offset.width - panX) > 0.05
            || abs(lastState.offset.height - panY) > 0.05 {
            lastState = ZoomState(scale: currentScale, offset: CGSize(width: panX, height: panY))
            onChange?(lastState)
        }
    }
}
