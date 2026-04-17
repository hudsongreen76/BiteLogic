import SwiftUI
import CoreData

@main
struct BiteLogicApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .task {
                    // Refresh notification permission status on every launch.
                    // First-launch permission prompt is triggered when the user
                    // enables notifications from the Dashboard settings card.
                    await NotificationManager.shared.refreshPermissionStatus()
                }
        }
    }
}
