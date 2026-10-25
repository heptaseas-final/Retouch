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
    case autoLightDebug
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

                Button("Auto Light Debug") {
                    path.append(MakeupRoute.autoLightDebug)
                }
                .buttonStyle(.bordered)
            }
            .navigationTitle("Home")
            .navigationDestination(for: MakeupRoute.self) { route in
                switch route {
                // TODO: replace with the HiFi eye makeup and contour flows
                case .eyeMakeup:
                    ContentUnavailableView("Eye Makeup", systemImage: "eye", description: Text("Coming soon"))
                case .contour:
                    ContentUnavailableView("Face Makeup", systemImage: "face.smiling", description: Text("Coming soon"))
                case .autoLightDebug:
                    DebugMirrorView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
