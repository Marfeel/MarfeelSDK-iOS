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
        // Clear storage for fresh start (debug only)
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let plistURL = documentsURL.appendingPathComponent("CompassPersistenceV2.plist")
            try? fileManager.removeItem(at: plistURL)
        }

        CompassTracker.initialize(accountId: 1659, pageTechnology: 105)
    }
}
