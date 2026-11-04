import Foundation

/// Zoom bibir sebagai satu alur dengan empat keadaan: diam, menghitung masuk, zoom aktif, menghitung lepas.
///
/// - Pemicu hanya dari jari: pose 2 jari atau pose 3 jari, masing-masing dengan timer sendiri.
/// - Penahan: jari di area dekat bibir (posisi saja, pose tidak dibaca) ATAU bibir bergerak. Salah satu cukup.
/// - Gerakan bibir tidak pernah memicu zoom.
/// - Lepas: dua penahan sama-sama hilang selama `releaseDwell`. Penahan muncul lagi = hitungan mulai dari awal.
nonisolated struct LipsZoomFlow {
    enum Phase: Equatable { case idle, entering, active, releasing }
    enum Trigger: Equatable { case twoFinger, threeFinger }

    struct Input {
        /// Pose 2 jari terbaca DAN lolos aturan salah picu (jari dekat bibir, pelan, bibir jelas lebih dekat dari mata).
        var pose2Ready = false
        /// Sama, untuk pose 3 jari.
        var pose3Ready = false
        /// Ada ujung jari di dalam area dekat bibir. Hanya posisi, pose tidak ikut dihitung.
        var fingerNear = false
        /// Bibir sedang bergerak (LipMotionRecognizer.isMoving).
        var lipsMoving = false
    }

    var enterDwell = ZoomTuning.lipsEnterDwell
    var releaseDwell = ZoomTuning.lipsReleaseDwell

    private(set) var phase: Phase = .idle
    private(set) var trigger: Trigger?       // pose yang memicu zoom yang sedang aktif (untuk log)
    private var pose2Since: Date?
    private var pose3Since: Date?
    private var releaseSince: Date?

    /// Zoom bibir sedang berlaku (termasuk saat hitungan lepas berjalan).
    var isActive: Bool { phase == .active || phase == .releasing }

    /// Sisa waktu sebelum zoom turun, untuk debug. nil kalau tidak sedang menghitung lepas.
    func releaseRemaining(now: Date) -> TimeInterval? {
        guard phase == .releasing, let since = releaseSince else { return nil }
        return max(releaseDwell - now.timeIntervalSince(since), 0)
    }

    /// Dipanggil setiap logika jalan. Mengembalikan apakah zoom bibir aktif.
    @discardableResult
    mutating func update(_ input: Input, now: Date) -> Bool {
        switch phase {
        case .idle, .entering:
            releaseSince = nil
            // Dua timer terpisah: masing-masing hanya jalan selama syaratnya terpenuhi terus-menerus
            pose2Since = input.pose2Ready ? (pose2Since ?? now) : nil
            pose3Since = input.pose3Ready ? (pose3Since ?? now) : nil

            let due2 = pose2Since.map { now.timeIntervalSince($0) >= enterDwell } ?? false
            let due3 = pose3Since.map { now.timeIntervalSince($0) >= enterDwell } ?? false
            if due2 || due3 {
                // Kalau dua-duanya sudah cukup, yang muncul lebih awal yang dihitung
                if due2, due3, let s2 = pose2Since, let s3 = pose3Since {
                    trigger = s2 < s3 ? .twoFinger : .threeFinger
                } else {
                    trigger = due2 ? .twoFinger : .threeFinger
                }
                pose2Since = nil
                pose3Since = nil
                phase = .active
            } else {
                phase = (pose2Since != nil || pose3Since != nil) ? .entering : .idle
            }

        case .active, .releasing:
            // Selama zoom aktif, pose tidak lagi memicu apa-apa
            pose2Since = nil
            pose3Since = nil
            if input.fingerNear || input.lipsMoving {
                releaseSince = nil
                phase = .active
            } else {
                if releaseSince == nil { releaseSince = now }
                phase = .releasing
                if let since = releaseSince, now.timeIntervalSince(since) >= releaseDwell {
                    goIdle()
                }
            }
        }
        return isActive
    }

    /// Dipakai saat target lain mengambil alih (mata, pinch, mode manual) atau sesi di-reset.
    mutating func cancel() { goIdle() }

    private mutating func goIdle() {
        phase = .idle
        trigger = nil
        pose2Since = nil
        pose3Since = nil
        releaseSince = nil
    }
}
