//
//  AudifuzzApp.swift
//  Audifuzz
//
//  Created by Zero Unity on 9/20/26.
//

import SwiftUI

@main
struct AudifuzzApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
