//
//  BearCutFishingApp.swift
//  BearCutFishing
//
//  Created by Hudson Green on 4/9/26.
//

import SwiftUI
import CoreData

@main
struct BearCutFishingApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
