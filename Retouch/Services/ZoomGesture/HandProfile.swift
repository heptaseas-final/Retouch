import Foundation

nonisolated struct HandProfile: Codable, Equatable {
    var enterDistance = 0.6       // jarak-antar-mata, kuas dianggap "dekat fitur"
    var maxIntentSpeed = 2.5      // jarak-antar-mata per detik
    var exitHold = 1.0            // detik, jeda sebelum turun tingkat

    mutating func clamp() {
        enterDistance = min(max(enterDistance, 0.4), 0.9)
        maxIntentSpeed = min(max(maxIntentSpeed, 1.5), 4.0)
        exitHold = min(max(exitHold, 0.7), 1.8)
    }

    /// Zoom muncul padahal tidak diminta: perketat.
    mutating func learnUnwanted() {
        enterDistance *= 0.93
        maxIntentSpeed *= 0.93
        clamp()
    }

    /// Pengguna zoom sendiri padahal auto belum jalan: longgarkan.
    mutating func learnMissed() {
        enterDistance *= 1.07
        maxIntentSpeed *= 1.05
        clamp()
    }
}

nonisolated enum HandProfileStore {
    private static let key = "zoom.handProfile.v1"

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
}
