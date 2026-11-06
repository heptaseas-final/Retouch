//
//  OnboardingView.swift
//  Retouch
//
//  Created by Gabriella Angelina Widjaja on 06/11/26.
//


import SwiftUI

struct OnboardingView<Camera: View>: View {
    @State private var coordinator: OnboardingCoordinator
    private let signalSource: any OnboardingSignalSource
    private let camera: (FacePart, LightMode) -> Camera

    private let pickerGlow = Color(red: 0.85, green: 0.30, blue: 0.40)
    private let flashGlow = Color(red: 0.76, green: 0.60, blue: 0.45)
    
    private let controlHeight: CGFloat = 46

    init(
        signalSource: any OnboardingSignalSource,
        autoPart: FacePart = .face,
        onFinish: @escaping () -> Void,
        @ViewBuilder camera: @escaping (FacePart, LightMode) -> Camera
    ) {
        _coordinator = State(initialValue: OnboardingCoordinator(autoPart: autoPart, onFinish: onFinish))
        self.signalSource = signalSource
        self.camera = camera
    }

    var body: some View {
        let step = coordinator.step

        ZStack {
            camera(coordinator.selectedPart, coordinator.lightMode)
                .ignoresSafeArea()

            Color.black
                .opacity(step.dimsBackdrop ? 0.65 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if step.showsHandOverlay {
                OnboardingHandOverlay(eyeAnchor: signalSource.eyeAnchor)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                topBar(for: step)
                bubble(at: .top)
                    .padding(.top, 8)
                Spacer(minLength: 0)
                bubble(at: .bottom)
                    .padding(.bottom, 16)
                controls(for: step)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .animation(.snappy, value: coordinator.step)
        .animation(.snappy, value: coordinator.isInstructionVisible)
        .onAppear {
            coordinator.attach(signalSource)
            coordinator.start()
        }
        .onDisappear {
            coordinator.detach(signalSource)
        }
    }

    // MARK: - Bagian layar

    private func topBar(for step: OnboardingStep) -> some View {
        HStack {
            Spacer()
            if step != .done {
                Button("Skip") { coordinator.skip() }
                    .font(.subheadline)
                    .underline()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private func bubble(at position: OnboardingBubblePosition) -> some View {
        if coordinator.step.bubblePosition == position,
           coordinator.isInstructionVisible,
           let text = coordinator.step.instruction {
            InstructionBubble(text: text)
                .id(text)
                .transition(.opacity)
        }
    }

    private func controls(for step: OnboardingStep) -> some View {
        CameraControls(
            part: Binding(
                get: { coordinator.selectedPart },
                set: { coordinator.selectPart($0) }
            ),
            lightMode: Binding(
                get: { coordinator.lightMode },
                set: { coordinator.lightMode = $0 }
            ),
            nextLightMode: { coordinator.nextLightMode(from: $0) },
            onLightTap: { _ in coordinator.flashTapped() },
            pickerEmphasis: step.focus == .picker ? .highlighted(pickerGlow) : .dimmed,
            flashEmphasis: step.focus == .flash ? .highlighted(flashGlow) : .dimmed,
            height: controlHeight
        )
    }
}

// MARK: - Preview

#Preview {
    struct Demo: View {
        @State private var source = MockOnboardingSignalSource()

        var body: some View {
            ZStack {
                OnboardingView(signalSource: source, onFinish: { print("Onboarding selesai") }) { part, light in
                    // Kamera palsu: warna mengikuti mode cahaya.
                    (light.lightColor?.color ?? Color(white: 0.35))
                        .overlay {
                            Text(part.title)
                                .font(.largeTitle)
                                .foregroundStyle(.black.opacity(0.25))
                        }
                }

                // Tombol debug untuk mensimulasikan sinyal dari Vision/modul zoom.
                HStack {
                    Button("Hand near eye") { source.send(.handNearEye) }
                    Button("Zoomed in") { source.send(.zoomedIn) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
    return Demo()
}

