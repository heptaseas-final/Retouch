//
//  ContentView.swift
//  Retouch
//
//  Created by Davin P on 21/10/26.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    let session: MirrorSession

    var body: some View {
        ZStack {
            MirrorView(session: session, showsControls: hasCompletedOnboarding)

            if !hasCompletedOnboarding {
                OnboardingFlow(session: session) {
                    withAnimation(.easeInOut) { hasCompletedOnboarding = true }
                }
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    ContentView(session: MirrorSession())
}
