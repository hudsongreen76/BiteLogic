import Foundation

// MARK: - Shared URLSession with reasonable timeout

private let apiSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 15
    return URLSession(configuration: config)
}()

// MARK: - Networking Error

enum APIError: LocalizedError {
    case badURL, networkError(Error), decodingError(Error), noData

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid URL"
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .noData: return "No data returned"
        }
    }
}

// MARK: - Tide Service (NOAA CO-OPS API)

class TideService {
    static let shared = TideService()

    func fetchTides(stationId: String, timezone: String, for date: Date = Date()) async throws -> [TideReading] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: timezone)
        let dateStr = formatter.string(from: date)

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        let endStr = formatter.string(from: tomorrow)

        let urlStr = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
            + "?begin_date=\(dateStr)&end_date=\(endStr)"
            + "&station=\(stationId)"
            + "&product=predictions&datum=MLLW&time_zone=lst_ldt"
            + "&interval=h&units=english&application=bitelogic&format=json"

        guard let url = URL(string: urlStr) else { throw APIError.badURL }

        let (data, _) = try await apiSession.data(from: url)
        do {
            let response = try JSONDecoder().decode(NOAAResponse.self, from: data)
            return response.predictions
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func findExtrema(from readings: [TideReading]) -> [TideExtrema] {
        guard readings.count >= 3 else { return [] }
        var extrema: [TideExtrema] = []
        for i in 1..<(readings.count - 1) {
            let prev = readings[i - 1].heightFt
            let curr = readings[i].heightFt
            let next = readings[i + 1].heightFt
            if curr > prev && curr > next {
                extrema.append(TideExtrema(time: readings[i].time, heightFt: curr, isHigh: true))
            } else if curr < prev && curr < next {
                extrema.append(TideExtrema(time: readings[i].time, heightFt: curr, isHigh: false))
            }
        }
        return extrema
    }

    func tideChangeRate(readings: [TideReading], at date: Date = Date()) -> Double {
        let sorted = readings.sorted { $0.time < $1.time }
        guard let idx = sorted.firstIndex(where: { $0.time > date }), idx > 0 else { return 0 }
        let before = sorted[idx - 1]
        let after = sorted[idx]
        let hrs = after.time.timeIntervalSince(before.time) / 3600.0
        guard hrs > 0 else { return 0 }
        return abs(after.heightFt - before.heightFt) / hrs
    }

    func fetchTides3Day(stationId: String, timezone: String, from date: Date = Date()) async throws -> [TideReading] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: timezone)

        let startOfDay = Calendar.current.startOfDay(for: date)
        let endDate = Calendar.current.date(byAdding: .day, value: 3, to: startOfDay)!

        let urlStr = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
            + "?begin_date=\(formatter.string(from: startOfDay))&end_date=\(formatter.string(from: endDate))"
            + "&station=\(stationId)"
            + "&product=predictions&datum=MLLW&time_zone=lst_ldt"
            + "&interval=h&units=english&application=bitelogic&format=json"

        guard let url = URL(string: urlStr) else { throw APIError.badURL }
        let (data, _) = try await apiSession.data(from: url)
        do {
            let response = try JSONDecoder().decode(NOAAResponse.self, from: data)
            return response.predictions
        } catch {
            throw APIError.decodingError(error)
        }
    }

    func fetchTidesForDate(stationId: String, timezone: String, date: Date) async throws -> [TideReading] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: timezone)

        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        let urlStr = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter"
            + "?begin_date=\(formatter.string(from: dayStart))&end_date=\(formatter.string(from: dayEnd))"
            + "&station=\(stationId)"
            + "&product=predictions&datum=MLLW&time_zone=lst_ldt"
            + "&interval=h&units=english&application=bitelogic&format=json"

        guard let url = URL(string: urlStr) else { throw APIError.badURL }
        let (data, _) = try await apiSession.data(from: url)
        do {
            let response = try JSONDecoder().decode(NOAAResponse.self, from: data)
            return response.predictions
        } catch {
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - Weather Service (Open-Meteo)

class WeatherService {
    static let shared = WeatherService()

    func fetchWeather(lat: Double, lon: Double, timezone: String) async throws -> WeatherData {
        let weatherURL = URL(string:
            "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=temperature_2m,wind_speed_10m,wind_direction_10m,surface_pressure"
            + "&temperature_unit=fahrenheit&wind_speed_unit=mph"
            + "&timezone=\(timezone)&forecast_days=1"
        )!

        let marineURL = URL(string:
            "https://marine-api.open-meteo.com/v1/marine"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=sea_surface_temperature"
            + "&temperature_unit=fahrenheit"
            + "&timezone=\(timezone)&forecast_days=1"
        )!

        let (weatherData, _) = try await apiSession.data(from: weatherURL)
        let weatherResponse = try JSONDecoder().decode(OpenMeteoResponse.self, from: weatherData)

        let marineResponse: MarineWeatherResponse? = await {
            do {
                let (data, _) = try await apiSession.data(from: marineURL)
                return try JSONDecoder().decode(MarineWeatherResponse.self, from: data)
            } catch {
                return nil
            }
        }()

        let hour = Calendar.current.component(.hour, from: Date())
        let idx = min(hour, weatherResponse.hourly.windSpeed10m.count - 1)

        let windMph = weatherResponse.hourly.windSpeed10m[idx]
        let windDir = compassDirection(degrees: weatherResponse.hourly.windDirection10m[idx])
        let airTemp = weatherResponse.hourly.temperature2m[idx]

        let waterTemp: Double
        let waterEstimated: Bool
        if let marine = marineResponse {
            let marineIdx = min(hour, marine.hourly.seaSurfaceTemperature.count - 1)
            waterTemp = marine.hourly.seaSurfaceTemperature[marineIdx] ?? (airTemp - 3)
            waterEstimated = marine.hourly.seaSurfaceTemperature[marineIdx] == nil
        } else {
            waterTemp = airTemp - 3
            waterEstimated = true
        }

        let pressures = weatherResponse.hourly.surfacePressure ?? []
        let pressure = idx < pressures.count ? pressures[idx] : 1013.0
        let pressureChange: Double
        if idx > 0, idx < pressures.count {
            pressureChange = pressures[idx] - pressures[idx - 1]
        } else {
            pressureChange = 0
        }

        return WeatherData(
            windMph: windMph,
            windDirection: windDir,
            waterTempF: waterTemp,
            airTempF: airTemp,
            pressureHpa: pressure,
            pressureChangeRate: pressureChange,
            timestamp: Date(),
            waterTempEstimated: waterEstimated
        )
    }

    func fetchHourlyWind(lat: Double, lon: Double, timezone: String) async throws -> [(hour: Int, mph: Double)] {
        let url = URL(string:
            "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=temperature_2m,wind_speed_10m,wind_direction_10m,surface_pressure"
            + "&temperature_unit=fahrenheit&wind_speed_unit=mph"
            + "&timezone=\(timezone)&forecast_days=1"
        )!
        let (data, _) = try await apiSession.data(from: url)
        let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return response.hourly.windSpeed10m.enumerated().map { ($0.offset, $0.element) }
    }

    func fetchWeather3Day(lat: Double, lon: Double, timezone: String) async throws -> OpenMeteoResponse {
        let url = URL(string:
            "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=temperature_2m,wind_speed_10m,wind_direction_10m,surface_pressure"
            + "&temperature_unit=fahrenheit&wind_speed_unit=mph"
            + "&timezone=\(timezone)&forecast_days=3"
        )!
        let (data, _) = try await apiSession.data(from: url)
        return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    }

    func fetchMarine3Day(lat: Double, lon: Double, timezone: String) async throws -> MarineWeatherResponse {
        let url = URL(string:
            "https://marine-api.open-meteo.com/v1/marine"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=sea_surface_temperature"
            + "&temperature_unit=fahrenheit"
            + "&timezone=\(timezone)&forecast_days=3"
        )!
        let (data, _) = try await apiSession.data(from: url)
        return try JSONDecoder().decode(MarineWeatherResponse.self, from: data)
    }

    func fetchHistoricalWeather(lat: Double, lon: Double, timezone: String, date: Date) async throws -> OpenMeteoResponse {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)

        let url = URL(string:
            "https://archive-api.open-meteo.com/v1/archive"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&start_date=\(dateStr)&end_date=\(dateStr)"
            + "&hourly=temperature_2m,wind_speed_10m,wind_direction_10m,surface_pressure"
            + "&temperature_unit=fahrenheit&wind_speed_unit=mph"
            + "&timezone=\(timezone)"
        )!
        let (data, _) = try await apiSession.data(from: url)
        return try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    }

    func compassDirection(degrees: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        let idx = Int((degrees / 22.5) + 0.5) % 16
        return dirs[idx]
    }
}
