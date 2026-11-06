//
//  RetouchApp.swift
//  Retouch
//
//  Created by Davin P on 21/10/26.
//

import SwiftUI

@main
struct RetouchApp: App {
    @State private var session = MirrorSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
        }
    }
}
