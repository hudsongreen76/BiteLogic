import Foundation
import SwiftUI
import CoreData
import Combine

@MainActor
class FishingViewModel: ObservableObject {

    // MARK: - Published State
    @Published var tideReadings: [TideReading] = []
    @Published var tideExtrema: [TideExtrema] = []
    @Published var currentTideHeight: Double = 0
    @Published var tideChangeRate: Double = 0
    @Published var currentTideStage: TideStage = .slack

    @Published var weather: WeatherData?
    @Published var hourlyWind: [(hour: Int, mph: Double)] = []

    @Published var moonPhase: MoonPhaseData = MoonPhaseData.calculate(for: Date())

    @Published var predictions: [UUID: VariablePrediction] = [:]

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    @Published var dailySummaries: [DailyConditionSummary] = []

    @Published var weatherIsDemo = false
    @Published var waterTempEstimated = false
    @Published var tidesIsDemo = false

    @Published var scrubbingIndex: Int? = nil

    // MARK: - Spot Reference
    var activeSpot: FishingSpotEntity?
    var viewContext: NSManagedObjectContext?

    private var spotLat: Double { activeSpot?.latitude ?? 25.7275 }
    private var spotLon: Double { activeSpot?.longitude ?? -80.1572 }
    private var spotStationId: String { activeSpot?.noaaStationId ?? "8723214" }
    private var spotTimezone: String { activeSpot?.timezone ?? "America/New_York" }

    // MARK: - Current Conditions

    var currentConditions: EnvironmentalConditions {
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        return EnvironmentalConditions(
            windMph: weather?.windMph ?? 0,
            windDirection: 0,
            tideHeight: currentTideHeight,
            tideChangeRate: tideChangeRate,
            tideStage: currentTideStage,
            moonPhase: moonPhase.phase,
            moonIllumination: moonPhase.illumination,
            waterTempF: weather?.waterTempF ?? 78,
            airTempF: weather?.airTempF ?? 80,
            pressureHpa: weather?.pressureHpa ?? 1013,
            pressureChangeRate: weather?.pressureChangeRate ?? 0,
            timeOfDay: Double(hour) + Double(minute) / 60.0,
            isDaylight: hour >= 6 && hour < 20,
            isEstimatedWaterTemp: weather?.waterTempEstimated ?? true
        )
    }

    // MARK: - Load All Data

    func loadAll() async {
        guard activeSpot != nil else { return }

        isLoading = true
        errorMessage = nil
        weatherIsDemo = false
        waterTempEstimated = false
        tidesIsDemo = false

        moonPhase = MoonPhaseData.calculate(for: Date())

        async let tidesTask: Void = loadTides()
        async let weatherTask: Void = loadWeather()
        async let summariesTask: Void = load3DaySummaries()

        await tidesTask
        await weatherTask
        await summariesTask

        computePredictions()
        lastUpdated = Date()
        isLoading = false
    }

    private func loadTides() async {
        do {
            let readings = try await TideService.shared.fetchTides(
                stationId: spotStationId, timezone: spotTimezone
            )
            tideReadings = readings
            tideExtrema = TideService.shared.findExtrema(from: readings)
            tideChangeRate = TideService.shared.tideChangeRate(readings: readings)

            let now = Date()
            let sorted = readings.sorted { $0.time < $1.time }
            if let idx = sorted.firstIndex(where: { $0.time > now }), idx > 0 {
                let before = sorted[idx - 1]
                let after = sorted[idx]
                let fraction = now.timeIntervalSince(before.time)
                    / after.time.timeIntervalSince(before.time)
                currentTideHeight = before.heightFt + fraction * (after.heightFt - before.heightFt)

                let diff = after.heightFt - before.heightFt
                if abs(diff) < 0.02 {
                    currentTideStage = .slack
                } else {
                    currentTideStage = diff > 0 ? .incoming : .outgoing
                }
            }
        } catch {
            errorMessage = "Tide data: \(error.localizedDescription)"
            tidesIsDemo = true
            tideReadings = Self.demoTides()
            tideExtrema = TideService.shared.findExtrema(from: tideReadings)
            tideChangeRate = 0.18
            currentTideHeight = 1.4
        }
    }

    private func loadWeather() async {
        do {
            let weatherData = try await WeatherService.shared.fetchWeather(
                lat: spotLat, lon: spotLon, timezone: spotTimezone
            )
            weather = weatherData
            waterTempEstimated = weatherData.waterTempEstimated
        } catch {
            errorMessage = (errorMessage ?? "") + "\nWeather: \(error.localizedDescription)"
            weatherIsDemo = true
            waterTempEstimated = true
            weather = WeatherData(windMph: 12, windDirection: "SE", waterTempF: 78,
                                  airTempF: 81, pressureHpa: 1013, pressureChangeRate: -0.3,
                                  timestamp: Date(), waterTempEstimated: true)
        }

        do {
            hourlyWind = try await WeatherService.shared.fetchHourlyWind(
                lat: spotLat, lon: spotLon, timezone: spotTimezone
            )
        } catch {
            hourlyWind = (0..<24).map { ($0, Double.random(in: 8...18)) }
        }
    }

    // MARK: - 3-Day Summaries

    private func load3DaySummaries() async {
        do {
            let weatherResponse = try await WeatherService.shared.fetchWeather3Day(
                lat: spotLat, lon: spotLon, timezone: spotTimezone
            )
            let weatherTimes = parseHourlyDates(weatherResponse.hourly.time)

            let marineResponse: MarineWeatherResponse? = await {
                do {
                    return try await WeatherService.shared.fetchMarine3Day(
                        lat: spotLat, lon: spotLon, timezone: spotTimezone
                    )
                } catch {
                    return nil
                }
            }()
            let marineTimes = marineResponse.map { parseHourlyDates($0.hourly.time) } ?? []
            let marineTemps = marineResponse?.hourly.seaSurfaceTemperature ?? []
            let marineUnavailable = marineResponse == nil

            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())

            var summaries: [DailyConditionSummary] = []
            for day in 0..<3 {
                let dayStart = calendar.date(byAdding: .day, value: day, to: startOfToday)!
                let dayEnd = calendar.date(byAdding: .day, value: day + 1, to: startOfToday)!

                let dayWindSpeeds = zip(weatherTimes, weatherResponse.hourly.windSpeed10m)
                    .filter { $0.0 >= dayStart && $0.0 < dayEnd }
                let dayWindDirs = zip(weatherTimes, weatherResponse.hourly.windDirection10m)
                    .filter { $0.0 >= dayStart && $0.0 < dayEnd }
                let dayPressures = zip(weatherTimes, weatherResponse.hourly.surfacePressure ?? [])
                    .filter { $0.0 >= dayStart && $0.0 < dayEnd }
                let dayAirTemps = zip(weatherTimes, weatherResponse.hourly.temperature2m)
                    .filter { $0.0 >= dayStart && $0.0 < dayEnd }

                let windSpeeds = dayWindSpeeds.map(\.1)
                let avgWind = windSpeeds.isEmpty ? 0 : windSpeeds.reduce(0, +) / Double(windSpeeds.count)
                let maxWind = windSpeeds.max() ?? 0

                let dirs = dayWindDirs.map(\.1)
                let avgDir = dirs.isEmpty ? 0 : dirs.reduce(0, +) / Double(dirs.count)

                let pressures = dayPressures.map(\.1)
                let avgPressure = pressures.isEmpty ? 1013 : pressures.reduce(0, +) / Double(pressures.count)
                let pressureTrend = pressures.count >= 2 ? (pressures.last! - pressures.first!) : 0

                let hourlyWindData = dayWindSpeeds.map { (calendar.component(.hour, from: $0.0), $0.1) }
                let hourlyPressure = dayPressures.map { (calendar.component(.hour, from: $0.0), $0.1) }

                let dayMarineTemps: [Double]
                if !marineTimes.isEmpty {
                    dayMarineTemps = zip(marineTimes, marineTemps)
                        .filter { $0.0 >= dayStart && $0.0 < dayEnd }
                        .compactMap { $0.1 }
                } else {
                    dayMarineTemps = []
                }

                let waterTemps: [Double]
                let waterEstimated: Bool
                if dayMarineTemps.isEmpty {
                    let airTemps = dayAirTemps.map(\.1)
                    waterTemps = airTemps.map { $0 - 3 }
                    waterEstimated = true
                } else {
                    waterTemps = dayMarineTemps
                    waterEstimated = marineUnavailable
                }

                let avgWaterTemp = waterTemps.isEmpty ? 78 : waterTemps.reduce(0, +) / Double(waterTemps.count)

                summaries.append(DailyConditionSummary(
                    date: dayStart,
                    avgWindMph: avgWind,
                    maxWindMph: maxWind,
                    avgWindDir: WeatherService.shared.compassDirection(degrees: avgDir),
                    hourlyWind: hourlyWindData,
                    avgWaterTempF: avgWaterTemp,
                    minWaterTempF: waterTemps.min() ?? avgWaterTemp,
                    maxWaterTempF: waterTemps.max() ?? avgWaterTemp,
                    avgPressureHpa: avgPressure,
                    pressureTrend: pressureTrend,
                    hourlyPressure: hourlyPressure,
                    waterTempEstimated: waterEstimated
                ))
            }
            dailySummaries = summaries
        } catch {
            dailySummaries = []
        }
    }

    private func parseHourlyDates(_ timeStrings: [String]) -> [Date] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: spotTimezone)
        return timeStrings.compactMap { formatter.date(from: $0) }
    }

    func computePredictions() {
        guard let spot = activeSpot else { return }
        let conditions = currentConditions
        let spotId = spot.id ?? UUID()

        // Compute baseline water temp from recent snapshots (10-day avg concept)
        let entries = spot.sortedLogEntries
        let recentSnapshots = entries
            .compactMap { $0.environmentalSnapshot }
            .filter { snap in
                guard let entry = snap.logEntry, let date = entry.date else { return false }
                return date.timeIntervalSinceNow > -10 * 86400
            }
        let baselineTemp: Double
        if !recentSnapshots.isEmpty {
            baselineTemp = recentSnapshots.map(\.waterTempF).reduce(0, +) / Double(recentSnapshots.count)
        } else {
            baselineTemp = conditions.waterTempF // use current as fallback
        }
        PredictionManager.shared.updateBaselineWaterTemp(baselineTemp, spotId: spotId)

        for variable in spot.sortedVariables {
            let varId = variable.id ?? UUID()

            // Build training data from log entries
            let trainingData: [(conditions: EnvironmentalConditions, rating: Double)] = entries.compactMap { entry -> (conditions: EnvironmentalConditions, rating: Double)? in
                guard let snapshot = entry.environmentalSnapshot,
                      let ratings = entry.ratings as? Set<VariableRatingEntity>,
                      let rating = ratings.first(where: { $0.variable?.id == varId }) else { return nil }
                return (conditions: snapshot.toConditions, rating: rating.ratingValue)
            }

            PredictionManager.shared.retrain(entries: trainingData, spotId: spotId, variableId: varId)

            let prediction = PredictionManager.shared.predict(
                conditions: conditions, spotId: spotId, variableId: varId
            )
            predictions[varId] = prediction
        }
    }

    // MARK: - Scrubbing helper

    func tideReadingForScrub() -> TideReading? {
        guard let idx = scrubbingIndex, tideReadings.indices.contains(idx) else { return nil }
        return tideReadings[idx]
    }

    // MARK: - Demo Data

    static func demoTides() -> [TideReading] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let heights: [Double] = [
            0.8, 0.5, 0.4, 0.6, 1.0, 1.6, 2.2, 2.6, 2.7, 2.5,
            2.0, 1.4, 0.9, 0.6, 0.5, 0.7, 1.1, 1.7, 2.3, 2.6,
            2.5, 2.1, 1.5, 1.0
        ]
        return heights.enumerated().map { idx, h in
            TideReading(time: start.addingTimeInterval(Double(idx) * 3600), heightFt: h)
        }
    }
}
