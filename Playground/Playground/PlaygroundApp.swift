//
//  PlaygroundApp.swift
//  Playground
//
//  Created by Marc García Lopez on 02/05/2023.
//

import SwiftUI
import MarfeelSDK_iOS

@main
struct PlaygroundApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    init() {
        CompassTracker.initialize(accountId: 0, pageTechnology: 105)
    }
}
