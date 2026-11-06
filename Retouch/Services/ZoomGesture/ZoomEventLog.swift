import Foundation

/// Satu kejadian auto zoom (target bukan full face).
nonisolated struct ZoomEvent {
    let target: String
    let start: Date
    var end: Date?
    var reason = ""
}

/// Ringkasan angka untuk debug overlay dan pengukuran sebelum/sesudah revisi.
nonisolated struct ZoomLogSummary {
    var sessionSeconds: TimeInterval = 0
    var zoomCount = 0
    var flipFlops = 0            // masuk lalu keluar (atau sebaliknya) dalam < ZoomTuning.flipFlopWindow
    var pinchOutAfterAuto = 0    // user pinch zoom out sesudah auto zoom muncul
    var pinchInWhileIdle = 0     // user pinch zoom in saat auto diam
    var pitchFreezes = 0         // berapa kali yaw dibekukan karena dongak cepat

    var zoomsPerMinute: Double {
        sessionSeconds >= 1 ? Double(zoomCount) / (sessionSeconds / 60) : 0
    }

    var text: String {
        String(format: "sesi %.1f mnt | zoom %d (%.1f/mnt) | flip-flop %d\npinch out %d | pinch in %d | freeze pitch %d",
               sessionSeconds / 60, zoomCount, zoomsPerMinute, flipFlops,
               pinchOutAfterAuto, pinchInWhileIdle, pitchFreezes)
    }
}

/// Catatan kejadian untuk testing. Hanya diakses di stateQueue milik service.
nonisolated struct ZoomEventLog {
    private(set) var events: [ZoomEvent] = []
    private var counts = ZoomLogSummary()
    private var sessionStart: Date?
    private var open: ZoomEvent?
    private var lastFullAt: Date?   // kapan terakhir kembali ke full face (untuk flip-flop sebaliknya)

    mutating func reset() {
        self = ZoomEventLog()
    }

    /// Dipanggil tiap keputusan baru. `endReason` hanya dievaluasi kalau target berubah.
    mutating func update(_ target: ZoomTarget, at now: Date, endReason: () -> String) {
        if sessionStart == nil { sessionStart = now }
        let name: String? = target == .fullFace ? nil : target.debugName
        if open?.target == name { return }
        if open != nil { close(reason: endReason(), at: now, toFull: name == nil) }
        if let name { begin(name, at: now) }
    }

    /// Tutup kejadian yang sedang berjalan tanpa dihitung sebagai flip-flop (reset, mode diganti).
    mutating func finish(reason: String, at now: Date) {
        close(reason: reason, at: now, toFull: false)
    }

    mutating func notePinchOutAfterAuto() { counts.pinchOutAfterAuto += 1 }
    mutating func notePinchInWhileIdle() { counts.pinchInWhileIdle += 1 }
    mutating func noteFreezes(_ n: Int) { counts.pitchFreezes += n }

    func summary(now: Date) -> ZoomLogSummary {
        var s = counts
        s.sessionSeconds = sessionStart.map { now.timeIntervalSince($0) } ?? 0
        return s
    }

    func exportText(now: Date, profileNote: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        var lines = ["Auto zoom log", summary(now: now).text, profileNote, "---"]
        for e in events + (open.map { [$0] } ?? []) {
            let end = e.end ?? now
            let reason = e.end == nil ? "(masih aktif)" : e.reason
            lines.append(String(format: "%@  %@  %.1fs  %@", f.string(from: e.start), e.target,
                                end.timeIntervalSince(e.start), reason))
        }
        return lines.joined(separator: "\n")
    }

    private mutating func begin(_ name: String, at now: Date) {
        if let t = lastFullAt, now.timeIntervalSince(t) < ZoomTuning.flipFlopWindow { counts.flipFlops += 1 }
        lastFullAt = nil
        open = ZoomEvent(target: name, start: now)
        counts.zoomCount += 1
    }

    private mutating func close(reason: String, at now: Date, toFull: Bool) {
        guard var e = open else { return }
        e.end = now
        e.reason = reason
        open = nil
        events.append(e)
        if events.count > ZoomTuning.eventLogCapacity { events.removeFirst(events.count - ZoomTuning.eventLogCapacity) }
        if toFull, now.timeIntervalSince(e.start) < ZoomTuning.flipFlopWindow { counts.flipFlops += 1 }
        lastFullAt = toFull ? now : nil
    }
}
