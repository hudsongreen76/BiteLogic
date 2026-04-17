import CoreData
import Foundation

// MARK: - Persistence Controller

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "BiteLogic")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Destroy and recreate store on migration failure (pre-release, no user data to preserve)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

        let localContainer = container
        localContainer.loadPersistentStores { description, error in
            if let error = error as NSError? {
                // If migration fails, destroy and recreate the store
                if let url = description.url {
                    try? FileManager.default.removeItem(at: url)
                    localContainer.loadPersistentStores { _, retryError in
                        if let retryError = retryError as NSError? {
                            fatalError("Core Data error after reset: \(retryError), \(retryError.userInfo)")
                        }
                    }
                } else {
                    fatalError("Core Data error: \(error), \(error.userInfo)")
                }
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Preview helper

    static var preview: PersistenceController = {
        let ctrl = PersistenceController(inMemory: true)
        let ctx = ctrl.container.viewContext

        // Create a sample spot
        let spot = FishingSpotEntity(context: ctx)
        spot.id = UUID()
        spot.name = "Bear Cut"
        spot.latitude = 25.7275
        spot.longitude = -80.1572
        spot.noaaStationId = "8723214"
        spot.timezone = "America/New_York"
        spot.createdAt = Date()

        // Add default tracked variable
        let activityVar = TrackedVariableEntity(context: ctx)
        activityVar.id = UUID()
        activityVar.name = "Fish Bite / Activity"
        activityVar.type = VariableType.stars.rawValue
        activityVar.isDefault = true
        activityVar.sortOrder = 0
        activityVar.spot = spot

        // Add sample log entries
        for i in 0..<5 {
            let entry = LogEntryEntity(context: ctx)
            entry.id = UUID()
            entry.date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            entry.startTime = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: entry.date!)
            entry.endTime = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: entry.date!)
            entry.notes = "Sample trip \(i + 1)"
            entry.createdAt = Date()
            entry.spot = spot

            let rating = VariableRatingEntity(context: ctx)
            rating.id = UUID()
            rating.ratingValue = Double.random(in: 1...5)
            rating.variable = activityVar
            rating.logEntry = entry

            let snapshot = EnvironmentalSnapshotEntity(context: ctx)
            snapshot.id = UUID()
            snapshot.windMph = Double.random(in: 5...20)
            snapshot.windDirection = Double.random(in: 0...360)
            snapshot.tideHeight = Double.random(in: 0...3)
            snapshot.tideChangeRate = Double.random(in: -0.3...0.3)
            snapshot.tideStage = [TideStage.incoming, .outgoing, .slack].randomElement()!.rawValue
            snapshot.moonPhase = Double.random(in: 0...1)
            snapshot.moonIllumination = Double.random(in: 0...1)
            snapshot.waterTempF = Double.random(in: 74...82)
            snapshot.airTempF = Double.random(in: 72...85)
            snapshot.pressureHpa = Double.random(in: 1010...1025)
            snapshot.pressureChangeRate = Double.random(in: -1...1)
            snapshot.timeOfDay = Double.random(in: 18...23)
            snapshot.isDaylight = false
            snapshot.logEntry = entry
        }

        try? ctx.save()
        return ctrl
    }()

    // MARK: - Save

    func save() {
        let ctx = container.viewContext
        guard ctx.hasChanges else { return }
        do {
            try ctx.save()
        } catch {
            print("Save error: \(error)")
        }
    }
}

// MARK: - FishingSpotEntity Helpers

extension FishingSpotEntity {
    var sortedVariables: [TrackedVariableEntity] {
        let set = trackedVariables as? Set<TrackedVariableEntity> ?? []
        return set.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sortedLogEntries: [LogEntryEntity] {
        let set = logEntries as? Set<LogEntryEntity> ?? []
        return set.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var toSpotInfo: SpotInfo {
        SpotInfo(
            id: id ?? UUID(),
            name: name ?? "Unknown",
            latitude: latitude,
            longitude: longitude,
            noaaStationId: noaaStationId ?? "",
            timezone: timezone ?? "America/New_York",
            createdAt: createdAt ?? Date()
        )
    }
}

// MARK: - LogEntryEntity Helpers

extension LogEntryEntity {
    func rating(for variable: TrackedVariableEntity) -> VariableRatingEntity? {
        let set = ratings as? Set<VariableRatingEntity> ?? []
        return set.first { $0.variable?.id == variable.id }
    }

    var snapshot: EnvironmentalSnapshotEntity? {
        environmentalSnapshot
    }
}

// MARK: - EnvironmentalSnapshotEntity Helpers

extension EnvironmentalSnapshotEntity {
    var toConditions: EnvironmentalConditions {
        EnvironmentalConditions(
            windMph: windMph,
            windDirection: windDirection,
            tideHeight: tideHeight,
            tideChangeRate: tideChangeRate,
            tideStage: TideStage(rawValue: tideStage ?? "slack") ?? .slack,
            moonPhase: moonPhase,
            moonIllumination: moonIllumination,
            waterTempF: waterTempF,
            airTempF: airTempF,
            pressureHpa: pressureHpa,
            pressureChangeRate: pressureChangeRate,
            precipitationMm: precipitationMm,
            waveHeightM: waveHeightM,
            wavePeriodS: wavePeriodS,
            cloudCoverPct: cloudCoverPct,
            windGustsMph: windGustsMph,
            timeOfDay: timeOfDay,
            isDaylight: isDaylight,
            isEstimatedWind: isEstimatedWind,
            isEstimatedWaterTemp: isEstimatedWaterTemp,
            isEstimatedPressure: isEstimatedPressure,
            isEstimatedTide: isEstimatedTide
        )
    }

    func populate(from conditions: EnvironmentalConditions) {
        windMph = conditions.windMph
        windDirection = conditions.windDirection
        tideHeight = conditions.tideHeight
        tideChangeRate = conditions.tideChangeRate
        tideStage = conditions.tideStage.rawValue
        moonPhase = conditions.moonPhase
        moonIllumination = conditions.moonIllumination
        waterTempF = conditions.waterTempF
        airTempF = conditions.airTempF
        pressureHpa = conditions.pressureHpa
        pressureChangeRate = conditions.pressureChangeRate
        precipitationMm = conditions.precipitationMm
        waveHeightM = conditions.waveHeightM
        wavePeriodS = conditions.wavePeriodS
        cloudCoverPct = conditions.cloudCoverPct
        windGustsMph = conditions.windGustsMph
        timeOfDay = conditions.timeOfDay
        isDaylight = conditions.isDaylight
        isEstimatedWind = conditions.isEstimatedWind
        isEstimatedWaterTemp = conditions.isEstimatedWaterTemp
        isEstimatedPressure = conditions.isEstimatedPressure
        isEstimatedTide = conditions.isEstimatedTide
    }
}
