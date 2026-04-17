import Foundation
import CoreData
import SwiftUI
import Combine

@MainActor
class SpotManager: ObservableObject {
    static let shared = SpotManager()

    @Published var activeSpot: FishingSpotEntity?
    @Published var spots: [FishingSpotEntity] = []

    private let activeSpotIdKey = "activeSpotId"

    var viewContext: NSManagedObjectContext?

    func loadSpots(context: NSManagedObjectContext) {
        viewContext = context
        let request = FishingSpotEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \FishingSpotEntity.createdAt, ascending: true)]
        spots = (try? context.fetch(request)) ?? []

        // Restore last active spot
        if let savedId = UserDefaults.standard.string(forKey: activeSpotIdKey),
           let uuid = UUID(uuidString: savedId),
           let match = spots.first(where: { $0.id == uuid }) {
            activeSpot = match
        } else {
            activeSpot = spots.first
        }
    }

    func setActiveSpot(_ spot: FishingSpotEntity) {
        activeSpot = spot
        UserDefaults.standard.set(spot.id?.uuidString, forKey: activeSpotIdKey)
    }

    func createSpot(
        name: String,
        latitude: Double,
        longitude: Double,
        noaaStationId: String,
        timezone: String
    ) -> FishingSpotEntity? {
        guard let context = viewContext else { return nil }

        let spot = FishingSpotEntity(context: context)
        spot.id = UUID()
        spot.name = name
        spot.latitude = latitude
        spot.longitude = longitude
        spot.noaaStationId = noaaStationId
        spot.timezone = timezone
        spot.createdAt = Date()

        // Add default tracking variable
        let activityVar = TrackedVariableEntity(context: context)
        activityVar.id = UUID()
        activityVar.name = "Fish Bite / Activity"
        activityVar.type = VariableType.stars.rawValue
        activityVar.isDefault = true
        activityVar.sortOrder = 0
        activityVar.spot = spot

        do {
            try context.save()
            spots.append(spot)
            setActiveSpot(spot)
            return spot
        } catch {
            context.rollback()
            return nil
        }
    }

    func deleteSpot(_ spot: FishingSpotEntity) {
        guard let context = viewContext else { return }
        let wasActive = spot == activeSpot
        context.delete(spot)
        try? context.save()
        spots.removeAll { $0 == spot }
        if wasActive {
            activeSpot = spots.first
            if let active = activeSpot {
                UserDefaults.standard.set(active.id?.uuidString, forKey: activeSpotIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: activeSpotIdKey)
            }
        }
    }
}
