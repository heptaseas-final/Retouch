//
//  HandProximityRecognizer.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//


import CoreGraphics
import Foundation

/// tangan / brush dekat mata atau mulut. Zoom pindah ke fitur yang lebih dekat.
nonisolated struct HandProximityRecognizer {
    var enterDistance: CGFloat = 0.12   // rasio terhadap tinggi layar
    var exitDistance: CGFloat = 0.18
    var switchRatio: CGFloat = 0.85     // pindah target kalau lebih dekat dari ini x jarak target sekarang
    var switchMargin: CGFloat = 0.015   // dan selisih jarak minimal ini (rasio tinggi layar), cegah bolak-balik
    var switchHold: TimeInterval = 0.0 // kandidat baru harus tetap terdekat selama ini

    private var filterX = OneEuroFilter()
    private var filterY = OneEuroFilter()
    private var lastHandTime: TimeInterval = 0
    private var prevHand: CGPoint?
    private var switchPending: (target: ZoomTarget, since: Date)?
    private var enterVotes: [Bool] = []
    private var holdVotes: [Bool] = []
    private(set) var current: ZoomTarget?

    /// Pilih tangan paling dekat ke wajah (tangan di paha diabaikan), lalu haluskan.
    mutating func trackHand(_ candidates: [CGPoint], points: FacePoints,
                            viewHeight H: CGFloat, now: Date) -> CGPoint? {
        guard !candidates.isEmpty else {
            prevHand = nil
            return nil
        }
        let anchors = points.handTargets.map { $0.1 }
        var chosen = candidates[0]
        if !anchors.isEmpty {
            var best = CGFloat.infinity
            for c in candidates {
                let d = anchors.map { hypot(c.x - $0.x, c.y - $0.y) }.min() ?? .infinity
                if d < best {
                    best = d
                    chosen = c
                }
            }
        }
        let t = now.timeIntervalSinceReferenceDate
        if t - lastHandTime > 0.3 {
            filterX.reset()
            filterY.reset()
        } else if let prev = prevHand, hypot(chosen.x - prev.x, chosen.y - prev.y) / H > 0.15 {
            filterX.reset()
            filterY.reset()
        }
        lastHandTime = t
        let nx = filterX.filter(Double(chosen.x / H), t: t)
        let ny = filterY.filter(Double(chosen.y / H), t: t)
        let p = CGPoint(x: CGFloat(nx) * H, y: CGFloat(ny) * H)
        prevHand = p
        return p
    }

    /// tangan di dekat wajah, posisinya dikunci.
    func isCovering(hand: CGPoint?, points: FacePoints, viewHeight H: CGFloat) -> Bool {
        guard let h = hand else { return false }
        return points.handTargets.contains {
            hypot(h.x - $0.1.x, h.y - $0.1.y) / H < exitDistance * 1.5
        }
    }

    mutating func update(hand: CGPoint?, points: FacePoints, viewHeight H: CGFloat, now: Date) -> ZoomTarget? {
        var best: (target: ZoomTarget, dist: CGFloat)?
        if let h = hand {
            for (target, p) in points.handTargets {
                let d = hypot(h.x - p.x, h.y - p.y) / H
                if d < (best?.dist ?? .infinity) { best = (target, d) }
            }
        }
        let dist = best?.dist ?? .infinity

        var holdDist = dist
        if let cur = current, let h = hand, let p = Self.position(of: cur, in: points) {
            holdDist = hypot(h.x - p.x, h.y - p.y) / H
        }
        Self.push(&enterVotes, dist < enterDistance)
        Self.push(&holdVotes, holdDist < exitDistance)
        let enterOK = enterVotes.filter { $0 }.count >= 3
        let holdOK = holdVotes.contains(true)

        guard let cur = current else {
            if enterOK { current = best?.target }
            return current
        }
        if !holdOK {
            current = nil
            switchPending = nil
            enterVotes = []
            holdVotes = []
            return current
        }
        var wantsSwitch = false
        if enterOK, let b = best, b.target != cur, let h = hand,
           let cp = Self.position(of: cur, in: points) {
            let curDist = hypot(h.x - cp.x, h.y - cp.y) / H
            wantsSwitch = b.dist < switchRatio * curDist && curDist - b.dist >= switchMargin
        }
        if wantsSwitch, let b = best {
            if switchPending?.target != b.target { switchPending = (b.target, now) }
            let bothEyes = (cur == .leftEye || cur == .rightEye) && (b.target == .leftEye || b.target == .rightEye)
            if let p = switchPending, now.timeIntervalSince(p.since) >= (bothEyes ? 0 : switchHold) {
                current = b.target
                holdVotes = [true]
                switchPending = nil
            }
        } else {
            switchPending = nil
        }
        return current
    }

    private static func position(of target: ZoomTarget, in p: FacePoints) -> CGPoint? {
        switch target {
        case .leftEye: p.leftEye
        case .rightEye: p.rightEye
        case .lips: p.lips
        default: nil
        }
    }

    private static func push(_ arr: inout [Bool], _ value: Bool) {
        arr.append(value)
        if arr.count > 5 { arr.removeFirst(arr.count - 5) }
    }
}
