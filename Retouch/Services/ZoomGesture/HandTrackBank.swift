import CoreGraphics
import Foundation

nonisolated struct TrackedHand {
    let id: Int
    var point: CGPoint      // ujung brush di ruang view, sudah dihaluskan
    var speed: CGFloat      // lebar wajah/detik, sudah dihaluskan
    var pose2: Bool
    var pose3: Bool
    var hasPose: Bool { pose2 || pose3 }
}

/// Melacak sampai beberapa tangan sekaligus, masing-masing dengan penghalus dan kecepatan sendiri.
/// Menggantikan pemilihan "satu tangan paling dekat wajah" supaya dua tangan tidak saling bergantian.
nonisolated struct HandTrackBank {
    struct Candidate {
        var tip: CGPoint
        var pose2: Bool
        var pose3: Bool
    }

    var jumpDistance: CGFloat = 0.9                        // lebar wajah; lebih jauh = tangan baru
    var speedTau = ZoomTuning.handSpeedTau
    var maxHandGap = ZoomTuning.handMaxGap
    var maxIntentSpeed = CGFloat(ZoomTuning.handMaxSpeed)

    private struct Track {
        let id: Int
        var fx = OneEuroFilter()
        var fy = OneEuroFilter()
        var time: TimeInterval
        var point: CGPoint
        var speed: CGFloat
    }
    private var tracks: [Track] = []
    private var nextID = 1

    mutating func apply(_ profile: HandProfile) {
        maxIntentSpeed = CGFloat(profile.maxIntentSpeed)
    }

    mutating func reset() { tracks = [] }

    /// Dipanggil hanya saat ada hasil deteksi tangan baru. Mengembalikan hanya tangan yang terlihat di deteksi ini.
    mutating func update(_ candidates: [Candidate], faceWidth W: CGFloat, viewHeight H: CGFloat,
                         now: Date) -> [TrackedHand] {
        guard W > 0 else {
            tracks = []
            return []
        }
        let t = now.timeIntervalSinceReferenceDate
        tracks.removeAll { t - $0.time > maxHandGap }

        // Cocokkan pasangan terdekat dulu
        var pairs: [(c: Int, k: Int, d: CGFloat)] = []
        for (ci, c) in candidates.enumerated() {
            for (ki, k) in tracks.enumerated() {
                let d = hypot(c.tip.x - k.point.x, c.tip.y - k.point.y) / W
                if d <= jumpDistance { pairs.append((ci, ki, d)) }
            }
        }
        pairs.sort { $0.d < $1.d }
        var matchOfCandidate: [Int: Int] = [:]
        var usedTracks = Set<Int>()
        for p in pairs where matchOfCandidate[p.c] == nil && !usedTracks.contains(p.k) {
            matchOfCandidate[p.c] = p.k
            usedTracks.insert(p.k)
        }

        var out: [TrackedHand] = []
        for (ci, c) in candidates.enumerated() {
            var track: Track
            let isNew: Bool
            if let ki = matchOfCandidate[ci] {
                track = tracks[ki]
                isNew = false
            } else {
                track = Track(id: nextID, time: t, point: c.tip, speed: maxIntentSpeed * 2)
                nextID += 1
                isNew = true
            }
            let dt = max(t - track.time, 0.001)
            let nx = track.fx.filter(Double(c.tip.x / H), t: t)
            let ny = track.fy.filter(Double(c.tip.y / H), t: t)
            let p = CGPoint(x: CGFloat(nx) * H, y: CGFloat(ny) * H)

            if !isNew {
                let instant = hypot(p.x - track.point.x, p.y - track.point.y) / W / CGFloat(dt)
                let alpha = CGFloat(1 - exp(-min(dt, ZoomTuning.maxStep) / Double(speedTau)))
                track.speed += alpha * (instant - track.speed)
            }
            // Tangan baru: kecepatan ditahan tinggi sampai terukur
            track.point = p
            track.time = t

            if let ki = matchOfCandidate[ci] { tracks[ki] = track } else { tracks.append(track) }
            out.append(TrackedHand(id: track.id, point: p, speed: track.speed,
                                   pose2: c.pose2, pose3: c.pose3))
        }
        return out
    }
}
