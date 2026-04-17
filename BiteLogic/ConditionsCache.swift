import Foundation

// MARK: - Codable Environmental Conditions

/// Lightweight Codable snapshot used for offline caching.
struct CachedConditions: Codable {
    var windMph: Double
    var windDirection: Double
    var tideHeight: Double
    var tideChangeRate: Double
    var tideStage: String
    var moonPhase: Double
    var moonIllumination: Double
    var waterTempF: Double
    var airTempF: Double
    var pressureHpa: Double
    var pressureChangeRate: Double
    var precipitationMm: Double
    var waveHeightM: Double
    var wavePeriodS: Double
    var cloudCoverPct: Double
    var windGustsMph: Double
    var timeOfDay: Double
    var isDaylight: Bool
    var isEstimatedWind: Bool
    var isEstimatedWaterTemp: Bool
    var isEstimatedPressure: Bool
    var isEstimatedTide: Bool

    init(from conditions: EnvironmentalConditions) {
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

    var toConditions: EnvironmentalConditions {
        EnvironmentalConditions(
            windMph: windMph,
            windDirection: windDirection,
            tideHeight: tideHeight,
            tideChangeRate: tideChangeRate,
            tideStage: TideStage(rawValue: tideStage) ?? .slack,
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
}

struct CachedWeatherData: Codable {
    let windMph: Double
    let windDirection: String
    let windGustsMph: Double
    let waterTempF: Double
    let airTempF: Double
    let pressureHpa: Double
    let pressureChangeRate: Double
    let precipitationMm: Double
    let waveHeightM: Double
    let wavePeriodS: Double
    let cloudCoverPct: Double
    let waterTempEstimated: Bool

    init(from weather: WeatherData) {
        windMph = weather.windMph
        windDirection = weather.windDirection
        windGustsMph = weather.windGustsMph
        waterTempF = weather.waterTempF
        airTempF = weather.airTempF
        pressureHpa = weather.pressureHpa
        pressureChangeRate = weather.pressureChangeRate
        precipitationMm = weather.precipitationMm
        waveHeightM = weather.waveHeightM
        wavePeriodS = weather.wavePeriodS
        cloudCoverPct = weather.cloudCoverPct
        waterTempEstimated = weather.waterTempEstimated
    }

    var toWeatherData: WeatherData {
        WeatherData(
            windMph: windMph,
            windDirection: windDirection,
            windGustsMph: windGustsMph,
            waterTempF: waterTempF,
            airTempF: airTempF,
            pressureHpa: pressureHpa,
            pressureChangeRate: pressureChangeRate,
            precipitationMm: precipitationMm,
            waveHeightM: waveHeightM,
            wavePeriodS: wavePeriodS,
            cloudCoverPct: cloudCoverPct,
            timestamp: Date(),
            waterTempEstimated: waterTempEstimated
        )
    }
}

/// A full cached data set for one spot, stored in UserDefaults.
struct SpotCache: Codable {
    let spotId: UUID
    let fetchedAt: Date
    let conditions: CachedConditions
    let weather: CachedWeatherData
    let hourlyWind: [Double]          // indexed by hour 0-23
    let tideReadingsData: Data?       // JSON-encoded [TideReading] — optional, may be empty

    /// How old this cache is in a human-readable form.
    var ageDescription: String {
        let interval = Date().timeIntervalSince(fetchedAt)
        if interval < 60 { return "just now" }
        if interval < 3_600 {
            let mins = Int(interval / 60)
            return "\(mins) min ago"
        }
        let hours = Int(interval / 3_600)
        return "\(hours) hr ago"
    }

    var isStale: Bool {
        // Cache older than 6 hours is considered stale
        Date().timeIntervalSince(fetchedAt) > 6 * 3_600
    }
}

// MARK: - Conditions Cache

/// Manages per-spot offline caching of environmental data in UserDefaults.
class ConditionsCache {
    static let shared = ConditionsCache()

    private func key(for spotId: UUID) -> String {
        "conditionsCache_\(spotId.uuidString)"
    }

    func save(
        spotId: UUID,
        conditions: EnvironmentalConditions,
        weather: WeatherData,
        hourlyWind: [(hour: Int, mph: Double)],
        tideReadings: [TideReading]
    ) {
        var windByHour = [Double](repeating: 0, count: 24)
        for item in hourlyWind where item.hour < 24 {
            windByHour[item.hour] = item.mph
        }

        let tideData = try? JSONEncoder().encode(tideReadings.map {
            ["t": ISO8601DateFormatter().string(from: $0.time),
             "h": String($0.heightFt)]
        })

        let cache = SpotCache(
            spotId: spotId,
            fetchedAt: Date(),
            conditions: CachedConditions(from: conditions),
            weather: CachedWeatherData(from: weather),
            hourlyWind: windByHour,
            tideReadingsData: tideData
        )

        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: key(for: spotId))
        }
    }

    func load(spotId: UUID) -> SpotCache? {
        guard let data = UserDefaults.standard.data(forKey: key(for: spotId)),
              let cache = try? JSONDecoder().decode(SpotCache.self, from: data) else {
            return nil
        }
        return cache
    }

    func clear(spotId: UUID) {
        UserDefaults.standard.removeObject(forKey: key(for: spotId))
    }
}
