import Foundation

nonisolated struct HeadProfile: Codable, Equatable {
    var yawBaseline = 0.0   // derajat, posisi "lurus" milik pengguna
    var turnPeak = 0.0      // derajat, puncak noleh yang biasa dilakukan (0 = belum belajar)
}

nonisolated enum HeadProfileStore {
    private static let key = "zoom.headProfile.v1"

    static func load() -> HeadProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let profile = try? JSONDecoder().decode(HeadProfile.self, from: data) else { return HeadProfile() }
        return profile
    }

    static func save(_ profile: HeadProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// Hapus hasil belajar tersimpan (untuk testing).
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
