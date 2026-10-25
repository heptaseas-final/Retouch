import SwiftUI

/// Edge-to-edge mirror with a debug HUD and the manual controls, for running
/// the PRD test cases on a device. Tap the mirror to show or hide the panels.
struct DebugMirrorView: View {
    @State private var detector = AutoLightDetector()
    @State private var showsPanels = false 

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MirrorPreview(detector: detector)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { showsPanels.toggle() } }

            stateOverlay

            if showsPanels, detector.cameraState == .running {
                VStack {
                    HStack {
                        debugPanel
                        Spacer()
                    }
                    Spacer()
                    controls
                }
                .padding()
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear { detector.start() }
        .onDisappear { detector.stop() }
    }

    // MARK: Camera states (PRD Epic 1)

    @ViewBuilder
    private var stateOverlay: some View {
        switch detector.cameraState {
        case .permissionDenied:
            message("Turn on the camera permission",
                    detail: "The mirror needs the front camera.",
                    action: ("Open Settings", detector.openSystemSettings))
        case .failed:
            message("Camera is not opened",
                    detail: "The front camera couldn't be started.",
                    action: ("Try again", detector.retryCameraSetup))
        case .reconnecting:
            VStack {
                Label("Reconnecting…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
            }
            .padding(.top)
        case .idle, .notDetermined, .starting, .running:
            EmptyView()
        }
    }

    private func message(_ title: String, detail: String, action: (String, () -> Void)) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action.0, action: action.1).buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    // MARK: Debug HUD

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Lux  \(detector.roomLux.map { "\(Int($0.rounded()))" } ?? "–")  \(detector.lightCondition?.rawValue ?? "…")")
            Text("Meas \(detector.measuredLux.map { "\(Int($0.rounded()))" } ?? "–") (incl. screen)")
            Text("Room \(detector.roomKelvin.map { "\(Int($0))K" } ?? "–")  → \(Int(detector.targetColorKelvin))K \(detector.manualColor == nil ? "auto" : "manual")")
            Text("Face \(detector.isFaceVisible ? "visible" : "hidden")")
            Text("Scr  \(Int(detector.appliedBrightness * 100))%  \(detector.manualBrightness == nil ? "auto" : "manual")")
            Text("Dim  \(Int(detector.dimLightLevel * 100))%")
        }
        .font(.caption.monospaced())
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.white)
    }

    // MARK: Manual override (PRD Epic 5)

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                Slider(value: brightnessBinding, in: 0.05...1)
                Image(systemName: "sun.max")
            }

            Picker("Color", selection: colorBinding) {
                Text("Auto").tag(ManualColorChoice?.none)
                ForEach(ManualColorChoice.allCases, id: \.self) {
                    Text($0.rawValue.capitalized).tag(Optional($0))
                }
            }
            .pickerStyle(.segmented)

            if detector.manualBrightness != nil || detector.manualColor != nil {
                Button("Back to Auto", action: detector.resetToAuto)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    /// Dragging the slider switches to manual; it shows the applied value while automatic.
    private var brightnessBinding: Binding<Double> {
        Binding(
            get: { detector.manualBrightness ?? detector.appliedBrightness },
            set: { detector.setManualBrightness($0) }
        )
    }

    /// Picking "Auto" resets both dimensions, as `resetToAuto()` does (SDD §4.5).
    private var colorBinding: Binding<ManualColorChoice?> {
        Binding(
            get: { detector.manualColor },
            set: { choice in
                if let choice { detector.setManualColor(choice) } else { detector.resetToAuto() }
            }
        )
    }
}
