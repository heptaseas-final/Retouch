import Foundation

/// Posisi kepala "lurus" (pitch netral) per pengguna, dipelajari pelan seperti baseline yaw.
nonisolated struct PitchProfile: Codable, Equatable {
    var pitchBaseline = 0.0   // derajat

    mutating func clamp() {
        pitchBaseline = min(max(pitchBaseline, -ZoomTuning.maxPitchBaseline), ZoomTuning.maxPitchBaseline)
    }
}

nonisolated enum PitchProfileStore {
    private static let key = "zoom.pitchProfile.v1"

    static func load() -> PitchProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              var profile = try? JSONDecoder().decode(PitchProfile.self, from: data) else { return PitchProfile() }
        profile.clamp()
        return profile
    }

    static func save(_ profile: PitchProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Membaca dongak. Hanya penguat: hasilnya (`isLifted`, `isFrozen`) tidak pernah memicu zoom sendiri.
/// - `isLifted`: kepala mendongak sedikit (dengan hysteresis dan dwell), memperkuat pemicu tangan.
/// - `isFrozen`: pitch sedang berubah cepat, keputusan yaw ditahan supaya tidak muncul zoom samping palsu.
nonisolated struct HeadPitchRecognizer {
    var tau = ZoomTuning.pitchTau
    var liftEnter = ZoomTuning.pitchLiftEnter
    var liftExit = ZoomTuning.pitchLiftExit
    var liftDwell = ZoomTuning.pitchLiftDwell
    var releaseDwell = ZoomTuning.pitchReleaseDwell
    var freezeRate = ZoomTuning.pitchFreezeRate
    var freezeHold = ZoomTuning.pitchFreezeHold
    var baselineTau = ZoomTuning.pitchBaselineTau
    var lostGrace: TimeInterval = 0.8
    var coverGrace: TimeInterval = ZoomTuning.coverGrace

    private(set) var profile: PitchProfile
    private(set) var isLifted = false
    private(set) var relative: Double?       // derajat terhadap baseline, positif = mendongak
    private(set) var rate = 0.0              // derajat/detik, bertanda
    private(set) var freezeCount = 0         // berapa kali yaw dibekukan sejak dibuat (untuk event log)

    private var smoothed: Double?
    private var lastTime: Date?
    private var lastSeen: Date?
    private var liftPending: Date?
    private var releasePending: Date?
    private var freezeUntil = Date.distantPast

    init(profile: PitchProfile = PitchProfile()) {
        var p = profile
        p.clamp()
        self.profile = p
    }

    func isFrozen(now: Date) -> Bool { now < freezeUntil }

    /// Dipanggil hanya saat ada hasil deteksi wajah baru. Beri `face = nil` saat tangan menutupi wajah
    /// (`covered = true`): status terakhir ditahan sampai `coverGrace`, lalu dilepas.
    mutating func update(face: FaceObservation?, learn: Bool, covered: Bool, now: Date) {
        guard ZoomTuning.pitchEnabled, let face, face.pitch.isFinite else {
            holdWhileLost(covered: covered, now: now)
            return
        }
        lastSeen = now
        let dt = max(lastTime.map { now.timeIntervalSince($0) } ?? ZoomTuning.nominalStep, 0.001)
        lastTime = now

        let previous = smoothed ?? face.pitch
        let alpha = 1 - exp(-min(dt, ZoomTuning.maxStep) / tau)
        let value = previous + alpha * (face.pitch - previous)
        smoothed = value
        rate = (value - previous) / dt
        let rel = value - profile.pitchBaseline
        relative = rel

        // Pitch berubah cepat: yaw tidak bisa dipercaya sebentar
        if abs(rate) > freezeRate {
            if now >= freezeUntil { freezeCount += 1 }
            freezeUntil = now + freezeHold
        }

        // Posisi lurus hanya dipelajari saat kepala dekat posisi lurus, stabil, dan tidak ada gesture
        if learn, !isLifted, liftPending == nil,
           abs(rel) < ZoomTuning.pitchLearnWindow, abs(rate) < freezeRate / 3 {
            let k = 1 - exp(-min(dt, ZoomTuning.maxStep) / baselineTau)
            profile.pitchBaseline += (value - profile.pitchBaseline) * k
            profile.clamp()
        }

        // Hysteresis + dwell: masuk di sudut besar, keluar di sudut kecil
        if !isLifted {
            releasePending = nil
            if rel >= liftEnter, abs(rate) <= freezeRate {
                if liftPending == nil { liftPending = now }
                if let since = liftPending, now.timeIntervalSince(since) >= liftDwell {
                    isLifted = true
                    liftPending = nil
                }
            } else {
                liftPending = nil
            }
        } else {
            liftPending = nil
            if rel < liftExit {
                if releasePending == nil { releasePending = now }
                if let since = releasePending, now.timeIntervalSince(since) >= releaseDwell {
                    isLifted = false
                    releasePending = nil
                }
            } else {
                releasePending = nil
            }
        }
    }

    private mutating func holdWhileLost(covered: Bool, now: Date) {
        let grace = covered ? max(lostGrace, coverGrace) : lostGrace
        if let seen = lastSeen, now.timeIntervalSince(seen) < grace { return }
        isLifted = false
        relative = nil
        rate = 0
        smoothed = nil
        lastTime = nil
        lastSeen = nil
        liftPending = nil
        releasePending = nil
    }
}
