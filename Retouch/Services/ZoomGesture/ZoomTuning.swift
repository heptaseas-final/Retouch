import Foundation
import CoreImage
import Vision

/// Semua angka auto zoom yang bisa dituning, dikumpulkan di satu tempat.
/// Semua angka adalah nilai awal, bukan nilai final.
nonisolated struct ZoomTuning {
    // MARK: - Laju deteksi (kali per detik)
    static let detectionRate = 12.0
    static let fairRate = 8.0
    static let seriousRate = 5.0
    static let idleRate = 6.0
    static let idleAfter: TimeInterval = 3.0
    static let idleFaceSpeed = 0.3
    static let idleYawRate = 25.0
    static let envCheckInterval: TimeInterval = 2.0

    // MARK: - Resolusi analisis Vision
    static let downscaleEnabled = true
    static let analysisWidth: CGFloat = 640

    // MARK: - Penghalus berbasis waktu (konstanta waktu, detik)
    static let yawTau = 0.15
    static let pointTau: CGFloat = 0.1
    static let scaleTau: CGFloat = 0.65
    static let handSpeedTau: CGFloat = 0.15
    // MARK: - Zoom samping (level tetap)
    static let sideZoom: CGFloat = 1.35
    static let sideEnterDwell: TimeInterval = 0.45
    static let sideExitDwell: TimeInterval = 0.9
    static let sideFocusStrength: CGFloat = 0.7

    // MARK: - Pemicu tangan (semua jarak dalam satuan lebar wajah yang sudah dihaluskan)
    static let handEnterDistance = 0.38
    static let handMaxSpeed = 1.2
    static let eyeEnterFactor: CGFloat = 0.85
    static let handEnterDwell: TimeInterval = 0.35
    static let eyeEnterDwell: TimeInterval = 0.4
    static let handWinMargin: CGFloat = 0.12
    static let handSwitchMargin: CGFloat = 0.12
    static let handSwitchDwell: TimeInterval = 0.3
    static let handHoldGrace: TimeInterval = 0.4
    static let coverDistance: CGFloat = 0.65
    static let coverGrace: TimeInterval = 1.8
    static let coverHold: TimeInterval = 1.8
    static let widthTau: CGFloat = 0.65
    
    // MARK: - Dwell resolver
    static let resolverSwitchDwell: TimeInterval = 0.15
    static let resolverLipsSwitchDwell: TimeInterval = 0.15
    static let resolverLipsFirstDwell: TimeInterval = 0.1

    // MARK: - Animasi zoom (konstanta waktu, detik)
    static let zoomInTau: CGFloat = 0.28
    static let zoomOutTau: CGFloat = 0.35

    // MARK: - Pembelajaran (Tahap 4)
    static let exitHold: TimeInterval = 1.2             // tetap, tidak lagi dipelajari
    static let minTurnEnter = 16.0                      // derajat, batas bawah ambang masuk noleh
    static let turnPeakDefault = 33.0                   // derajat, puncak noleh awal kalau belum ada data
    static let turnLearnMinEpisode: TimeInterval = 1.0  // detik noleh yang sudah menetap sebelum dicatat
    static let turnLearnStep = 0.1                      // langkah belajar puncak noleh (dulu 0,25)
    static let turnLearnSessionCap = 6.0                // derajat, geser maksimum turnPeak dari awal pemakaian
    static let turnUnwantedStep = 2.0                   // derajat, naik per koreksi "zoom samping tidak diminta"
    static let sideCorrectionWindow: TimeInterval = 6.0 // pinch keluar sekian detik setelah zoom samping muncul = tidak diminta
    static let sideCorrectionAfterEnd: TimeInterval = 3.0
    static let handLearnSessionRange = 0.15             // +-15% dari nilai awal pemakaian
    static let headRearmEnabled = true                  // zoom samping diblok setelah aktivitas tangan sampai kepala lurus sekali
    static let headRearmStraight: TimeInterval = 0.3    // kepala harus lurus sekian detik sebelum zoom samping boleh lagi
    static let eventLogCapacity = 500
    static let flipFlopWindow: TimeInterval = 1.5

    // MARK: - Pitch / dongak (Tahap 5). Semua nilai awal, perlu dikalibrasi dengan debug overlay
    static let pitchEnabled = true                // saklar utama; false = perilaku persis seperti sebelum Tahap 5
    static let pitchYawFreezeEnabled = true       // bekukan keputusan yaw saat dongak cepat
    static let pitchHandSupportEnabled = true     // dongak memperkuat pemicu tangan (mata/bibir)
    static let pitchNominalRatio = 0.6            // rasio mata-hidung / mata-bibir saat kepala lurus (baseline menyerap selisih)
    static let pitchNoseGain = 0.4                // seberapa besar hidung bergeser per tan(pitch)
    static let pitchMaxYaw = 35.0                 // derajat; yaw lebih besar dari ini, pitch dianggap tidak valid
    static let pitchTau = 0.2                     // detik, penghalus pitch
    static let pitchLiftEnter = 6.0               // derajat relatif baseline: dianggap mendongak
    static let pitchLiftExit = 3.0                // derajat: dianggap tidak mendongak lagi
    static let pitchLiftDwell: TimeInterval = 0.2
    static let pitchReleaseDwell: TimeInterval = 0.3
    static let pitchFreezeRate = 40.0             // derajat/detik: lebih cepat dari ini yaw dibekukan
    static let pitchFreezeHold: TimeInterval = 0.35
    static let pitchLearnWindow = 8.0             // derajat dari baseline yang masih boleh dipelajari
    static let pitchBaselineTau = 6.0             // detik
    static let maxPitchBaseline = 10.0            // derajat
    static let pitchLipsReach: CGFloat = 1.15     // radius masuk bibir x ini saat mendongak
    static let pitchLipsDwellFactor: TimeInterval = 0.6
    static let pitchEyeReach: CGFloat = 1.1
    static let pitchEyeDwellFactor: TimeInterval = 0.75

    // MARK: - Batas waktu antar deteksi
    static let handMaxGap: TimeInterval = 0.5
    static let maxStep: TimeInterval = 0.35
    static let nominalStep: TimeInterval = 1.0 / 12.0
}

/// Hasil deteksi lengkap dengan cap waktu dan nomor urut yang bertambah.
nonisolated struct DetectionSnapshot<Value> {
    let value: Value
    let sequence: Int
    let timestamp: Date
}

/// Pembatas laju: menerima frame hanya kalau sudah waktunya. Dipakai di dalam lock milik detektor.
nonisolated struct RateGate {
    private var nextDue: TimeInterval = 0

    mutating func allow(now: TimeInterval, interval: TimeInterval) -> Bool {
        guard interval > 0 else { return true }
        if now < nextDue - 0.004 { return false }
        let next = nextDue + interval
        nextDue = next > now ? next : now + interval
        return true
    }
}

/// Menentukan jarak antar deteksi berdasarkan suhu perangkat, Low Power Mode, dan gerakan.
nonisolated struct DetectionPacer {
    private var lastMotion = Date()
    private var baseRate = ZoomTuning.detectionRate
    private var lastEnvCheck = Date.distantPast

    mutating func noteMotion(at now: Date) { lastMotion = now }

    mutating func interval(now: Date) -> TimeInterval {
        if now.timeIntervalSince(lastEnvCheck) >= ZoomTuning.envCheckInterval {
            lastEnvCheck = now
            let info = ProcessInfo.processInfo
            switch info.thermalState {
            case .nominal: baseRate = ZoomTuning.detectionRate
            case .fair: baseRate = ZoomTuning.fairRate
            default: baseRate = ZoomTuning.seriousRate
            }
            if info.isLowPowerModeEnabled { baseRate = min(baseRate, ZoomTuning.seriousRate) }
        }
        var rate = baseRate
        if now.timeIntervalSince(lastMotion) >= ZoomTuning.idleAfter {
            rate = min(rate, ZoomTuning.idleRate)
        }
        return 1 / rate
    }
}

/// Membuat handler Vision dari gambar yang sudah diperkecil (kalau diaktifkan).
nonisolated enum AnalysisImage {
    static func handler(for pixelBuffer: CVPixelBuffer) -> VNImageRequestHandler {
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let target = ZoomTuning.analysisWidth
        guard ZoomTuning.downscaleEnabled, width > target * 1.2 else {
            return VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored)
        }
        let scale = target / width
        let image = CIImage(cvPixelBuffer: pixelBuffer).applyingFilter(
            "CILanczosScaleTransform",
            parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1.0]
        )
        return VNImageRequestHandler(ciImage: image, orientation: .leftMirrored)
    }
}
