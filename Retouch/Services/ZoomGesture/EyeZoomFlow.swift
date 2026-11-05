import Foundation

nonisolated struct EyeZoomFlow {
    enum Phase: Equatable { case idle, entering, active, releasing }

    struct Input {
        /// Ada tangan berpose jepit di lingkaran trigger mata itu, dan lolos aturan salah picu
        /// (gerak pelan, mata itu jelas lebih dekat dari bibir). Semua tangan dievaluasi.
        var poseLeft = false
        var poseRight = false
        /// Ada ujung jari mana pun di zona tahan mata itu (tanpa melihat pose).
        var holdLeft = false
        var holdRight = false
        var activityLeft: EyeActivity = .idle
        var activityRight: EyeActivity = .idle
        /// Pengali dwell masuk (dongak memperpendek, mis. 0,75). Radius tidak lagi dipengaruhi dongak.
        var enterDwellFactor: TimeInterval = 1
    }

    var enterDwell = ZoomTuning.eyeFlowEnterDwell
    var switchDwell = ZoomTuning.eyeFlowSwitchDwell
    var releaseDwell = ZoomTuning.eyeFlowReleaseDwell

    private(set) var phase: Phase = .idle
    private(set) var side: EyeSide?          // mata yang sedang di-zoom
    private var leftSince: Date?
    private var rightSince: Date?
    private var switchPending: (side: EyeSide, since: Date)?
    private var releaseSince: Date?

    var isActive: Bool { phase == .active || phase == .releasing }

    /// Target untuk resolver: nil kalau tidak aktif.
    var target: ZoomTarget? {
        guard isActive, let side else { return nil }
        return side == .left ? .leftEye : .rightEye
    }

    func releaseRemaining(now: Date) -> TimeInterval? {
        guard phase == .releasing, let since = releaseSince else { return nil }
        return max(releaseDwell - now.timeIntervalSince(since), 0)
    }

    @discardableResult
    mutating func update(_ input: Input, now: Date) -> ZoomTarget? {
        switch phase {
        case .idle, .entering:
            leftSince = input.poseLeft ? (leftSince ?? now) : nil
            rightSince = input.poseRight ? (rightSince ?? now) : nil
            let need = enterDwell * input.enterDwellFactor
            let dueL = leftSince.map { now.timeIntervalSince($0) >= need } ?? false
            let dueR = rightSince.map { now.timeIntervalSince($0) >= need } ?? false
            if dueL || dueR {
                // Dua-duanya sudah cukup: yang muncul lebih awal yang dihitung
                if dueL, dueR, let l = leftSince, let r = rightSince {
                    side = l <= r ? .left : .right
                } else {
                    side = dueL ? .left : .right
                }
                begin()
            } else {
                phase = (leftSince != nil || rightSince != nil) ? .entering : .idle
            }

        case .active, .releasing:
            guard let current = side else {
                goIdle()
                break
            }
            leftSince = nil
            rightSince = nil
            let other: EyeSide = current == .left ? .right : .left
            let poseHere = current == .left ? input.poseLeft : input.poseRight
            let poseThere = other == .left ? input.poseLeft : input.poseRight

            // Pindah: pose hanya di mata satunya. Kalau dua-duanya ada pose, tetap di mata sekarang.
            if poseThere && !poseHere {
                if switchPending?.side != other { switchPending = (other, now) }
                if let p = switchPending, now.timeIntervalSince(p.since) >= switchDwell {
                    side = other
                    switchPending = nil
                    releaseSince = nil
                    phase = .active
                    return target
                }
            } else {
                switchPending = nil
            }

            let handHold = current == .left ? input.holdLeft : input.holdRight
            let activity = current == .left ? input.activityLeft : input.activityRight
            // .unknown = data hilang, ditahan (batasnya diatur EyeActivityRecognizer)
            let holding = handHold || activity == .active || activity == .unknown || activity == .turning
            if holding {
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
        return target
    }

    /// Dipakai saat target lain mengambil alih (bibir, pinch, mode manual) atau sesi di-reset.
    mutating func cancel() { goIdle() }

    private mutating func begin() {
        phase = .active
        leftSince = nil
        rightSince = nil
        switchPending = nil
        releaseSince = nil
    }

    private mutating func goIdle() {
        phase = .idle
        side = nil
        leftSince = nil
        rightSince = nil
        switchPending = nil
        releaseSince = nil
    }
}
