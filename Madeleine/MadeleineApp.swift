//
//  MadeleineApp.swift
//  Madeleine
//
//  Created by satoshikobayashi on 2026/04/19.
//

import SwiftUI
import SwiftData

@main
struct MadeleineApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            VlogProject.self,
            VlogClip.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none  // TODO: Re-enable after CloudKit container is set up: .private("iCloud.com.shakshi.Madeleine")
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
