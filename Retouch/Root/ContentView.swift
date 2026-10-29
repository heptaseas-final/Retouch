//
//  ContentView.swift
//  Retouch
//
//  Created by Davin P on 21/10/26.
//

import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainView()
                    .transition(.opacity)
            } else {
                OnboardingView {
                    withAnimation {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: hasCompletedOnboarding)
    }
    
}


struct MainView: View {
    var body: some View {
        MirrorView()
    }
}

#Preview {
    ContentView()
}
