//
//  ZoomGestureResolver.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//
import Foundation

nonisolated struct ZoomGestureResolver {
    var exitHold: TimeInterval = 2.0          // tanpa gesture selama ini, zoom out
    var switchDwell: TimeInterval = 0.2
    var lipsSwitchDwell: TimeInterval = 0.6   // pindah ke bibir dari target lain
    var lipsFirstDwell: TimeInterval = 0.6    // zoom pertama ke bibir dari full face
    var handCooldown: TimeInterval = 0.5      // kepala ditekan setelah tangan hilang
    var exitCooldown: TimeInterval = 1.0      // kepala ditekan setelah zoom out

    private(set) var target: ZoomTarget = .fullFace
    private var lastActive = Date.distantPast
    private var lastHandSeen = Date.distantPast
    private var lastExit = Date.distantPast
    private var pending: (target: ZoomTarget, since: Date)?

    mutating func resolve(hand: ZoomTarget?, head: ZoomTarget?, now: Date) -> ZoomTarget {
        if hand != nil { lastHandSeen = now }
        let headAllowed = now.timeIntervalSince(lastHandSeen) >= handCooldown
            && now.timeIntervalSince(lastExit) >= exitCooldown

        guard let candidate = hand ?? (headAllowed ? head : nil) else {
            pending = nil
            if target != .fullFace, now.timeIntervalSince(lastActive) >= exitHold {
                target = .fullFace
                lastExit = now
            }
            return target
        }

        lastActive = now
        if candidate == target {
            pending = nil
            return target
        }
        if pending?.target != candidate { pending = (candidate, now) }

        let isFirst = target == .fullFace
        let dwell: TimeInterval
        if candidate == .lips {
            dwell = isFirst ? lipsFirstDwell : lipsSwitchDwell
        } else {
            dwell = isFirst ? 0 : switchDwell
        }
        if let p = pending, now.timeIntervalSince(p.since) >= dwell {
            target = candidate
            pending = nil
        }
        return target
    }

    func idleTime(now: Date) -> TimeInterval {
        target == .fullFace ? 0 : now.timeIntervalSince(lastActive)
    }
}
