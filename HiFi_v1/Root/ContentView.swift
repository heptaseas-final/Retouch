//
//  ContentView.swift
//  HiFi_v1
//
//  Created by Davin P on 21/10/26.
//

import SwiftUI

enum MakeupRoute: Hashable {
    case eyeMakeup
    case contour
}

struct ContentView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                Button("Eye Makeup") {
                    path.append(MakeupRoute.eyeMakeup)
                }
                .buttonStyle(.borderedProminent)

                Button("Face Makeup") {
                    path.append(MakeupRoute.contour)
                }
                .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Home")
            .navigationDestination(for: MakeupRoute.self) { route in
                switch route {
                case .eyeMakeup:
                    EyeMakeupFlowView(onFinish: goHome)
                case .contour:
                    ContourFlowView(onFinish: goHome)
                }
            }
        }
    }

    private func goHome() {
        path = NavigationPath()
    }
}

#Preview {
    ContentView()
}
