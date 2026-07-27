//
//  aiboApp.swift
//  aibo
//
//  Created by fenx on 2026/7/27.
//

import AiboIngest
import SwiftUI

@main
struct aiboApp: App {
    init() {
        // Keep the local package link exercised while UI is still a scaffold.
        _ = AiboIngest.moduleName
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
