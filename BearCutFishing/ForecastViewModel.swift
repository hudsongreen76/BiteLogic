import Foundation
import SwiftUI

@MainActor
class ForecastViewModel: ObservableObject {

    // MARK: - Published State
    @Published var forecastDays: [ForecastDay] = []
    @Published var allBlocks: [ForecastBlock] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedBlockIndex: Int? = nil

    var selectedBlock: ForecastBlock? {
        guard let idx = selectedBlockIndex, allBlocks.indices.contains(idx) else { return nil }
        return allBlocks[idx]
    }

    // Spot parameters
    var spotLat: Double = 25.7275
    var spotLon: Double = -80.1572
    var spotStationId: String = "8723214"
    var spotTimezone: String = "America/New_York"
    var spotId: UUID = UUID()
    var trackedVariableIds: [UUID] = []

    // MARK: - Load Forecast

    func loadForecast() async {
        isLoading = true
        errorMessage = nil

        do {
            let tideReadings = try await TideService.shared.fetchTides3Day(
                stationId: spotStationId, timezone: spotTimezone
            )
            let weatherResponse = try await WeatherService.shared.fetchWeather3Day(
                lat: spotLat, lon: spotLon, timezone: spotTimezone
            )

            let marineResponse: MarineWeatherResponse? = await {
                do {
                    return try await WeatherService.shared.fetchMarine3Day(
                        lat: spotLat, lon: spotLon, timezone: spotTimezone
                    )
                } catch {
                    return nil
                }
            }()

            let weatherHours = parseHourlyDates(weatherResponse.hourly.time)
            let marineHours = marineResponse.map { parseHourlyDates($0.hourly.time) } ?? []
            let marineTemps: [Double?] = marineResponse?.hourly.seaSurfaceTemperature ??
                weatherResponse.hourly.temperature2m.map { Optional($0 - 3) }

            let blocks = buildForecastBlocks(
                tides: tideReadings,
                weatherTimes: weatherHours,
                windSpeeds: weatherResponse.hourly.windSpeed10m,
                windDirections: weatherResponse.hourly.windDirection10m,
                airTemps: weatherResponse.hourly.temperature2m,
                pressures: weatherResponse.hourly.surfacePressure ?? [],
                marineTimes: marineHours.isEmpty ? weatherHours : marineHours,
                waterTemps: marineTemps
            )

            allBlocks = blocks
            forecastDays = groupByDay(blocks)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Build 2-Hour Blocks

    private func buildForecastBlocks(
        tides: [TideReading],
        weatherTimes: [Date],
        windSpeeds: [Double],
        windDirections: [Double],
        airTemps: [Double],
        pressures: [Double],
        marineTimes: [Date],
        waterTemps: [Double?]
    ) -> [ForecastBlock] {

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        var blocks: [ForecastBlock] = []

        for day in 0..<3 {
            let dayStart = calendar.date(byAdding: .day, value: day, to: startOfToday)!
            for slot in 0..<12 {
                let blockStart = calendar.date(byAdding: .hour, value: slot * 2, to: dayStart)!
                let blockEnd = calendar.date(byAdding: .hour, value: (slot + 1) * 2, to: dayStart)!
                let blockMid = blockStart.addingTimeInterval(3600)

                let avgWind = averageInWindow(times: weatherTimes, values: windSpeeds,
                                              from: blockStart, to: blockEnd) ?? 10
                let avgWindDir = averageInWindow(times: weatherTimes, values: windDirections,
                                                 from: blockStart, to: blockEnd) ?? 0
                let avgAirTemp = averageInWindow(times: weatherTimes, values: airTemps,
                                                 from: blockStart, to: blockEnd) ?? 80

                let waterTempValues = waterTemps.compactMap { $0 }
                let avgWaterTemp = averageInWindow(times: marineTimes, values: waterTempValues,
                                                   from: blockStart, to: blockEnd) ?? (avgAirTemp - 3)

                let avgPressure = averageInWindow(times: weatherTimes, values: pressures,
                                                  from: blockStart, to: blockEnd) ?? 1013
                let pressureRate = pressureChangeRate(times: weatherTimes, values: pressures,
                                                     from: blockStart, to: blockEnd)

                let tideHeight = interpolateTide(tides: tides, at: blockMid)
                let tideRate = TideService.shared.tideChangeRate(readings: tides, at: blockMid)
                let moon = MoonPhaseData.calculate(for: blockMid)
                let hour = calendar.component(.hour, from: blockMid)
                let minute = calendar.component(.minute, from: blockMid)

                // Derive tide stage for this block
                let tideStage: TideStage
                let sorted = tides.sorted { $0.time < $1.time }
                if let idx = sorted.firstIndex(where: { $0.time > blockMid }), idx > 0 {
                    let diff = sorted[idx].heightFt - sorted[idx - 1].heightFt
                    if abs(diff) < 0.02 {
                        tideStage = .slack
                    } else {
                        tideStage = diff > 0 ? .incoming : .outgoing
                    }
                } else {
                    tideStage = .slack
                }

                let conditions = EnvironmentalConditions(
                    windMph: avgWind,
                    windDirection: avgWindDir,
                    tideHeight: tideHeight,
                    tideChangeRate: tideRate,
                    tideStage: tideStage,
                    moonPhase: moon.phase,
                    moonIllumination: moon.illumination,
                    waterTempF: avgWaterTemp,
                    airTempF: avgAirTemp,
                    pressureHpa: avgPressure,
                    pressureChangeRate: pressureRate,
                    timeOfDay: Double(hour) + Double(minute) / 60.0,
                    isDaylight: hour >= 6 && hour < 20
                )

                var preds: [UUID: VariablePrediction] = [:]
                for varId in trackedVariableIds {
                    preds[varId] = PredictionManager.shared.predict(
                        conditions: conditions, spotId: spotId, variableId: varId
                    )
                }

                blocks.append(ForecastBlock(
                    startTime: blockStart,
                    endTime: blockEnd,
                    conditions: conditions,
                    predictions: preds
                ))
            }
        }
        return blocks
    }

    // MARK: - Helpers

    private func averageInWindow(times: [Date], values: [Double],
                                 from: Date, to: Date) -> Double? {
        let pairs = zip(times, values).filter { $0.0 >= from && $0.0 < to }
        guard !pairs.isEmpty else { return nil }
        return pairs.map(\.1).reduce(0, +) / Double(pairs.count)
    }

    private func pressureChangeRate(times: [Date], values: [Double],
                                    from: Date, to: Date) -> Double {
        let window = zip(times, values)
            .filter { $0.0 >= from && $0.0 < to }
            .sorted { $0.0 < $1.0 }
        guard window.count >= 2 else { return 0 }
        let first = window.first!
        let last = window.last!
        let hours = last.0.timeIntervalSince(first.0) / 3600.0
        guard hours > 0 else { return 0 }
        return (last.1 - first.1) / hours
    }

    private func interpolateTide(tides: [TideReading], at date: Date) -> Double {
        let sorted = tides.sorted { $0.time < $1.time }
        guard let idx = sorted.firstIndex(where: { $0.time > date }), idx > 0 else {
            return sorted.last?.heightFt ?? 0
        }
        let before = sorted[idx - 1]
        let after = sorted[idx]
        let fraction = date.timeIntervalSince(before.time) / after.time.timeIntervalSince(before.time)
        return before.heightFt + fraction * (after.heightFt - before.heightFt)
    }

    private func parseHourlyDates(_ timeStrings: [String]) -> [Date] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: spotTimezone)
        return timeStrings.compactMap { formatter.date(from: $0) }
    }

    private func groupByDay(_ blocks: [ForecastBlock]) -> [ForecastDay] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: blocks) { block in
            calendar.startOfDay(for: block.startTime)
        }
        return grouped.keys.sorted().map { date in
            ForecastDay(date: date, blocks: grouped[date]!)
        }
    }
}
