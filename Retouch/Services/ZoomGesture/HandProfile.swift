import Foundation

/// Semua jarak dan kecepatan dalam satuan lebar wajah (yang sudah dihaluskan).
/// `exitHold` tidak lagi dipelajari: nilainya tetap di `ZoomTuning.exitHold`.
nonisolated struct HandProfile: Codable, Equatable {
    var enterDistance = ZoomTuning.handEnterDistance   // lebar wajah, kuas dianggap "dekat fitur"
    var maxIntentSpeed = ZoomTuning.handMaxSpeed       // lebar wajah per detik

    // Nilai di awal pemakaian, dipakai membatasi total geser per sesi. Tidak disimpan.
    private var anchorEnter: Double?
    private var anchorSpeed: Double?

    private enum CodingKeys: String, CodingKey { case enterDistance, maxIntentSpeed }

    mutating func clamp() {
        enterDistance = min(max(enterDistance, 0.25), 0.55)
        maxIntentSpeed = min(max(maxIntentSpeed, 0.8), 2.0)
        let r = ZoomTuning.handLearnSessionRange
        if let a = anchorEnter { enterDistance = min(max(enterDistance, a * (1 - r)), a * (1 + r)) }
        if let a = anchorSpeed { maxIntentSpeed = min(max(maxIntentSpeed, a * (1 - r)), a * (1 + r)) }
    }

    /// Panggil sekali saat app mulai: nilai tersimpan jadi titik awal, dan belajar hanya boleh
    /// menggesernya sejauh `handLearnSessionRange`.
    mutating func beginSession() {
        clamp()
        anchorEnter = enterDistance
        anchorSpeed = maxIntentSpeed
    }

    private mutating func ensureAnchor() {
        if anchorEnter == nil { anchorEnter = enterDistance }
        if anchorSpeed == nil { anchorSpeed = maxIntentSpeed }
    }

    /// Zoom muncul padahal tidak diminta: perketat.
    mutating func learnUnwanted() {
        ensureAnchor()
        enterDistance *= 0.93
        maxIntentSpeed *= 0.93
        clamp()
    }

    /// Pengguna zoom sendiri padahal auto belum jalan: longgarkan.
    mutating func learnMissed() {
        ensureAnchor()
        enterDistance *= 1.07
        maxIntentSpeed *= 1.05
        clamp()
    }
}

nonisolated enum HandProfileStore {
    // v2: satuan berubah dari jarak-antar-mata ke lebar wajah, nilai v1 tidak berlaku lagi
    private static let key = "zoom.handProfile.v2"

    static func load() -> HandProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              var profile = try? JSONDecoder().decode(HandProfile.self, from: data) else { return HandProfile() }
        profile.clamp()
        return profile
    }

    static func save(_ profile: HandProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Hapus hasil belajar tersimpan (untuk testing).
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
