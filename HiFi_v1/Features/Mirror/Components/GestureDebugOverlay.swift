//
//  GestureDebugOverlay.swift
//  HiFi_v1
//
//  Created by Davin P on 26/10/26.
//
import SwiftUI

struct GestureDebugOverlay: View {
    let viewModel: MirrorViewModel

    var body: some View {
        let info = viewModel.debugInfo
        VStack(alignment: .leading, spacing: 2) {
            Text("target : \(info.target)")
            Text("jarak  : L \(fmt(info.distLeftEye)) | R \(fmt(info.distRightEye)) | bibir \(fmt(info.distLips))")
            Text("tangan : lihat \(info.handsSeen) | jepit \(info.gripCount)")
            Text("jepit  : rasio \(fmt(info.pinchRatio)) | yakin \(String(format: "%.2f", info.handConfidence))")
            Text("kepala : yaw \(Int(info.yaw))° | turun \(String(format: "%.3f", info.down)) | \(info.headState)")
            Text("rasio  : \(String(format: "%.3f", info.ratio)) | dasar \(String(format: "%.3f", info.baseline))")
            Text("wajah  : tinggi/lebar \(String(format: "%.3f", info.faceAspect))")
            Text(String(format: "tahan  : %.1fs / %.1fs", info.idleTime, info.exitHold))
            Text("fps    : kamera \(info.fps) | tangan \(info.handFps)")
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 8)
        .padding(.leading, 16)
        .allowsHitTesting(false)
    }

    private func fmt(_ value: CGFloat?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "-"
    }
}
