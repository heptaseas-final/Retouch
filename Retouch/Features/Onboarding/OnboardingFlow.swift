//
//  OnboardingFlow.swift
//  Retouch
//

import SwiftUI

struct OnboardingFlow: View {
    let session: MirrorSession
    let onFinish: () -> Void
    @State private var signals: ZoomOnboardingSignals

    init(session: MirrorSession, onFinish: @escaping () -> Void) {
        self.session = session
        self.onFinish = onFinish
        _signals = State(initialValue: ZoomOnboardingSignals(session: session))
    }

    var body: some View {
        OnboardingView(signalSource: signals, onFinish: finish) { part, light in
            OnboardingCameraControl(session: session, part: part, light: light)
        }
        .onAppear { signals.connect() }
        .onDisappear { signals.disconnect() }
    }

    private func finish() {
        signals.disconnect()
        session.resetToDefaults()
        onFinish()
    }
}

struct OnboardingCameraControl: View {
    let session: MirrorSession
    let part: FacePart
    let light: LightMode

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .onChange(of: part, initial: true) { _, part in apply(part) }
            .onChange(of: light) { _, light in apply(light) }
    }

    private func apply(_ part: FacePart) { session.select(part) }
    private func apply(_ light: LightMode) { session.setLightMode(light) }
}
