//
//  ZoomGestureResolver.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//

import Foundation

nonisolated struct ZoomGestureResolver {
    var exitHold: TimeInterval = 3.0
    var switchDwell: TimeInterval = 0.2
    var lipsSwitchDwell: TimeInterval = 0.6

    private(set) var target: ZoomTarget = .fullFace
    private var lastActive = Date.distantPast
    private var pending: (target: ZoomTarget, since: Date)?

    mutating func resolve(hand: ZoomTarget?, head: ZoomTarget?, now: Date) -> ZoomTarget {
        guard let candidate = hand ?? head else {
            pending = nil
            if target != .fullFace, now.timeIntervalSince(lastActive) >= exitHold {
                target = .fullFace
            }
            return target
        }

        lastActive = now
        if candidate == target {
            pending = nil
        } else if target == .fullFace {
            target = candidate   // zoom pertama: langsung
            pending = nil
        } else {
            if pending?.target != candidate { pending = (candidate, now) }
            let dwell = candidate == .lips ? lipsSwitchDwell : switchDwell
            if let p = pending, now.timeIntervalSince(p.since) >= dwell {
                target = candidate
                pending = nil
            }
        }
        return target
    }
}
