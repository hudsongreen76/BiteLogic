import Foundation

struct FetchFailure {
    let dataType: String
    let error: Error
}

struct FetchResult {
    let conditions: EnvironmentalConditions
    let failures: [FetchFailure]
}

/// Fetches all environmental data for a spot at a given date/time.
/// Uses forecast APIs for today/future, historical APIs for past dates.
class EnvironmentalDataFetcher {
    static let shared = EnvironmentalDataFetcher()

    func fetch(
        lat: Double,
        lon: Double,
        stationId: String,
        timezone: String,
        date: Date,
        startHour: Int,
        endHour: Int,
        onProgress: ((Double, String) -> Void)? = nil
    ) async -> FetchResult {
        let midHour = (startHour + endHour) / 2
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()
        let useForecast = isToday || isFuture

        var conditions = EnvironmentalConditions()
        var failures: [FetchFailure] = []

        // Moon (always available - local calculation)
        onProgress?(0.1, "Calculating moon phase…")
        let moon = MoonPhaseData.calculate(for: date)
        conditions.moonPhase = moon.phase
        conditions.moonIllumination = moon.illumination

        // Time of day
        conditions.timeOfDay = Double(midHour)
        conditions.isDaylight = midHour >= 6 && midHour < 20

        // Parallel fetch: tides + weather
        onProgress?(0.2, "Fetching tides…")
        async let tideTask = fetchTides(stationId: stationId, timezone: timezone, date: date)
        async let weatherTask = fetchWeather(lat: lat, lon: lon, timezone: timezone, date: date, hour: midHour, useForecast: useForecast)

        // Process tides
        let tideResult = await tideTask
        onProgress?(0.55, "Fetching weather…")
        switch tideResult {
        case .success(let readings):
            let stageInfo = TideStageCalculator.blockTideInfo(
                blockStart: calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: date) ?? date,
                blockEnd: calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: date) ?? date,
                readings: readings
            )
            conditions.tideHeight = stageInfo.height
            conditions.tideChangeRate = stageInfo.changeRate
            conditions.tideStage = stageInfo.stage
        case .failure(let error):
            failures.append(FetchFailure(dataType: "Tides", error: error))
            conditions.isEstimatedTide = true
        }

        // Process weather
        let weatherResult = await weatherTask
        switch weatherResult {
        case .success(let weather):
            conditions.windMph = weather.windMph
            conditions.windDirection = weather.windDirDegrees
            conditions.windGustsMph = weather.windGustsMph
            conditions.airTempF = weather.airTempF
            conditions.waterTempF = weather.waterTempF
            conditions.pressureHpa = weather.pressureHpa
            conditions.pressureChangeRate = weather.pressureChangeRate
            conditions.precipitationMm = weather.precipitationMm
            conditions.waveHeightM = weather.waveHeightM
            conditions.wavePeriodS = weather.wavePeriodS
            conditions.cloudCoverPct = weather.cloudCoverPct
            conditions.isEstimatedWaterTemp = weather.waterTempEstimated
            conditions.isEstimatedPressure = weather.pressureEstimated
            conditions.isEstimatedWind = weather.windEstimated
        case .failure(let error):
            failures.append(FetchFailure(dataType: "Weather", error: error))
            conditions.isEstimatedWind = true
            conditions.isEstimatedPressure = true
            conditions.isEstimatedWaterTemp = true
        }

        onProgress?(1.0, "")
        return FetchResult(conditions: conditions, failures: failures)
    }

    // MARK: - Tide Fetch

    private func fetchTides(stationId: String, timezone: String, date: Date) async -> Result<[TideReading], Error> {
        do {
            let readings = try await TideService.shared.fetchTidesForDate(
                stationId: stationId, timezone: timezone, date: date
            )
            return .success(readings)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Weather Fetch

    struct WeatherSnapshot {
        let windMph: Double
        let windDirDegrees: Double
        let windGustsMph: Double
        let airTempF: Double
        let waterTempF: Double
        let pressureHpa: Double
        let pressureChangeRate: Double
        let precipitationMm: Double
        let waveHeightM: Double
        let wavePeriodS: Double
        let cloudCoverPct: Double
        let waterTempEstimated: Bool
        let pressureEstimated: Bool
        let windEstimated: Bool
    }

    private func fetchWeather(lat: Double, lon: Double, timezone: String, date: Date, hour: Int, useForecast: Bool) async -> Result<WeatherSnapshot, Error> {
        do {
            let response: OpenMeteoResponse
            if useForecast {
                response = try await WeatherService.shared.fetchWeather3Day(lat: lat, lon: lon, timezone: timezone)
            } else {
                response = try await WeatherService.shared.fetchHistoricalWeather(lat: lat, lon: lon, timezone: timezone, date: date)
            }

            let idx = min(hour, response.hourly.windSpeed10m.count - 1)
            guard idx >= 0 else { throw APIError.noData }

            let windMph = response.hourly.windSpeed10m[idx]
            let windDir = response.hourly.windDirection10m[idx]
            let airTemp = response.hourly.temperature2m[idx]
            let pressures = response.hourly.surfacePressure ?? []
            let pressure = idx < pressures.count ? pressures[idx] : 1013.0
            let pressureChange: Double
            if idx > 0, idx < pressures.count {
                pressureChange = pressures[idx] - pressures[idx - 1]
            } else {
                pressureChange = 0
            }

            let precip = response.hourly.precipitation.flatMap { arr in
                idx < arr.count ? arr[idx] : nil
            } ?? 0.0
            let cloud = response.hourly.cloudCover.flatMap { arr in
                idx < arr.count ? arr[idx] : nil
            } ?? 0.0
            let gusts = response.hourly.windGusts10m.flatMap { arr in
                idx < arr.count ? arr[idx] : nil
            } ?? windMph

            // Water temp + wave data from marine API
            let waterTemp: Double
            let waterEstimated: Bool
            var waveHeight = 0.0
            var wavePeriod = 0.0
            do {
                let marine = try await WeatherService.shared.fetchMarine3Day(lat: lat, lon: lon, timezone: timezone)
                let mi = min(hour, marine.hourly.seaSurfaceTemperature.count - 1)
                if mi >= 0, let sst = marine.hourly.seaSurfaceTemperature[mi] {
                    waterTemp = sst
                    waterEstimated = false
                } else {
                    waterTemp = airTemp - 3
                    waterEstimated = true
                }
                if let wh = marine.hourly.waveHeight, mi < wh.count { waveHeight = wh[mi] ?? 0.0 }
                if let wp = marine.hourly.wavePeriod, mi < wp.count { wavePeriod = wp[mi] ?? 0.0 }
            } catch {
                waterTemp = airTemp - 3
                waterEstimated = true
            }

            return .success(WeatherSnapshot(
                windMph: windMph,
                windDirDegrees: windDir,
                windGustsMph: gusts,
                airTempF: airTemp,
                waterTempF: waterTemp,
                pressureHpa: pressure,
                pressureChangeRate: pressureChange,
                precipitationMm: precip,
                waveHeightM: waveHeight,
                wavePeriodS: wavePeriod,
                cloudCoverPct: cloud,
                waterTempEstimated: waterEstimated,
                pressureEstimated: false,
                windEstimated: false
            ))
        } catch {
            return .failure(error)
        }
    }
}
