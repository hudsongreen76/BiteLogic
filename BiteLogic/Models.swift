import Foundation
import SwiftUI

// MARK: - Tide Models

struct TideReading: Identifiable, Codable {
    let id = UUID()
    let time: Date
    let heightFt: Double

    /// Set this before decoding NOAA responses to use the correct timezone.
    static var decodingTimezone: String = "America/New_York"

    enum CodingKeys: String, CodingKey {
        case time = "t"
        case heightFt = "v"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timeStr = try container.decode(String.self, forKey: .time)
        let heightStr = try container.decode(String.self, forKey: .heightFt)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: TideReading.decodingTimezone)
        self.time = formatter.date(from: timeStr) ?? Date()
        self.heightFt = Double(heightStr) ?? 0.0
    }

    init(time: Date, heightFt: Double) {
        self.time = time
        self.heightFt = heightFt
    }
}

struct TideExtrema: Identifiable {
    let id = UUID()
    let time: Date
    let heightFt: Double
    let isHigh: Bool
    var label: String { isHigh ? "High" : "Low" }
}

struct NOAAResponse: Codable {
    let predictions: [TideReading]
}

// MARK: - Tide Stage

enum TideStage: String, Codable, CaseIterable {
    case incoming = "incoming"
    case outgoing = "outgoing"
    case slack = "slack"

    var label: String {
        switch self {
        case .incoming: return "Incoming"
        case .outgoing: return "Outgoing"
        case .slack: return "Slack"
        }
    }

    var icon: String {
        switch self {
        case .incoming: return "arrow.up.forward"
        case .outgoing: return "arrow.down.forward"
        case .slack: return "pause.circle"
        }
    }
}

// MARK: - Variable Types

enum VariableType: String, Codable, CaseIterable {
    case stars = "stars"
    case category = "category"
}

// MARK: - Weather / Wind / Temp Models

struct WeatherData {
    let windMph: Double
    let windDirection: String
    let waterTempF: Double
    let airTempF: Double
    let pressureHpa: Double
    let pressureChangeRate: Double
    let timestamp: Date
    var waterTempEstimated: Bool = false
}

// MARK: - Environmental Conditions (universal input for predictions + snapshots)

struct EnvironmentalConditions {
    var windMph: Double = 0
    var windDirection: Double = 0         // degrees 0-360
    var tideHeight: Double = 0
    var tideChangeRate: Double = 0        // ft/hr
    var tideStage: TideStage = .slack
    var moonPhase: Double = 0             // 0-1
    var moonIllumination: Double = 0      // 0-1
    var waterTempF: Double = 0
    var airTempF: Double = 0
    var pressureHpa: Double = 0
    var pressureChangeRate: Double = 0    // hPa/hr
    var timeOfDay: Double = 0             // fractional hours 0-24
    var isDaylight: Bool = true

    // Estimation flags
    var isEstimatedWind: Bool = false
    var isEstimatedWaterTemp: Bool = false
    var isEstimatedPressure: Bool = false
    var isEstimatedTide: Bool = false
}

// MARK: - Spot Info (in-memory representation)

struct SpotInfo: Identifiable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let noaaStationId: String
    let timezone: String
    let createdAt: Date
}

// MARK: - 3-Day Condition Summary (per day)

struct DailyConditionSummary: Identifiable {
    let id = UUID()
    let date: Date
    let avgWindMph: Double
    let maxWindMph: Double
    let avgWindDir: String
    let hourlyWind: [(hour: Int, mph: Double)]
    let avgWaterTempF: Double
    let minWaterTempF: Double
    let maxWaterTempF: Double
    let avgPressureHpa: Double
    let pressureTrend: Double
    let hourlyPressure: [(hour: Int, hPa: Double)]
    let waterTempEstimated: Bool

    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

struct OpenMeteoResponse: Codable {
    let hourly: HourlyData
    struct HourlyData: Codable {
        let time: [String]
        let windSpeed10m: [Double]
        let windDirection10m: [Double]
        let temperature2m: [Double]
        let surfacePressure: [Double]?
        enum CodingKeys: String, CodingKey {
            case time
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case temperature2m = "temperature_2m"
            case surfacePressure = "surface_pressure"
        }
    }
}

struct MarineWeatherResponse: Codable {
    let hourly: MarineHourly
    struct MarineHourly: Codable {
        let time: [String]
        let seaSurfaceTemperature: [Double?]
        enum CodingKeys: String, CodingKey {
            case time
            case seaSurfaceTemperature = "sea_surface_temperature"
        }
    }
}

// MARK: - Moon Model

struct MoonPhaseData {
    let phase: Double
    let phaseName: String
    let illumination: Double
    let emoji: String

    var isNewMoon: Bool { phase < 0.07 || phase > 0.93 }
    var isFullMoon: Bool { phase > 0.43 && phase < 0.57 }

    static func calculate(for date: Date) -> MoonPhaseData {
        let knownNewMoon = Date(timeIntervalSince1970: 947182440)
        let synodicMonth = 29.530588853
        let elapsed = date.timeIntervalSince(knownNewMoon)
        let daysElapsed = elapsed / 86400.0
        var phase = (daysElapsed.truncatingRemainder(dividingBy: synodicMonth)) / synodicMonth
        if phase < 0 { phase += 1.0 }

        let illumination = (1 - cos(2 * Double.pi * phase)) / 2

        let phaseName: String
        let emoji: String
        switch phase {
        case 0..<0.025, 0.975...1.0:
            phaseName = "New Moon"; emoji = "🌑"
        case 0.025..<0.25:
            phaseName = "Waxing Crescent"; emoji = "🌒"
        case 0.25..<0.275:
            phaseName = "First Quarter"; emoji = "🌓"
        case 0.275..<0.475:
            phaseName = "Waxing Gibbous"; emoji = "🌔"
        case 0.475..<0.525:
            phaseName = "Full Moon"; emoji = "🌕"
        case 0.525..<0.725:
            phaseName = "Waning Gibbous"; emoji = "🌖"
        case 0.725..<0.75:
            phaseName = "Last Quarter"; emoji = "🌗"
        default:
            phaseName = "Waning Crescent"; emoji = "🌘"
        }

        return MoonPhaseData(phase: phase, phaseName: phaseName, illumination: illumination, emoji: emoji)
    }
}

// MARK: - Prediction Mode

enum PredictionMode: String, Codable, CaseIterable {
    case heuristic = "heuristic"
    case learned = "learned"

    var label: String {
        switch self {
        case .heuristic: return "Default"
        case .learned: return "Learned"
        }
    }

    var description: String {
        switch self {
        case .heuristic: return "Uses preset assumptions about fishing conditions"
        case .learned: return "Learns what works from your logged trips"
        }
    }

    var icon: String {
        switch self {
        case .heuristic: return "gearshape"
        case .learned: return "brain"
        }
    }
}

// MARK: - Heuristic User Preferences (for optional factors)

struct HeuristicPreferences: Codable {
    // Time of day: nil = no effect, "night" = night better, "day" = day better
    var timePreference: String? = nil
    // Moon phase: nil = no effect, "new" = new moon better, "full" = full moon better
    var moonPreference: String? = nil
    // Tide stage: nil = no effect, "incoming" = incoming better, "outgoing" = outgoing better
    var tideStagePreference: String? = nil

    static let defaultPreferences = HeuristicPreferences()

    static func load() -> HeuristicPreferences {
        guard let data = UserDefaults.standard.data(forKey: "heuristicPreferences"),
              let prefs = try? JSONDecoder().decode(HeuristicPreferences.self, from: data) else {
            return .defaultPreferences
        }
        return prefs
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "heuristicPreferences")
        }
    }
}

// MARK: - Prediction Output Types

struct PredictionFactor {
    let name: String
    let score: Double         // 0.0 to 1.0 (individual factor score)
    let weight: Double        // 0.0 to 1.0 (how much this factor contributes)
    let contribution: Double  // score * weight
    let note: String
    let color: Color

    static func colorForScore(_ score: Double) -> Color {
        if score >= 0.7 { return .green }
        if score >= 0.5 { return .orange }
        if score >= 0.3 { return .red }
        return .gray
    }
}

struct VariablePrediction {
    let predictedRating: Double           // 1-5 scale
    let percentage: Double                // 0-100 scale (old system)
    let confidenceInterval: (low: Double, high: Double)
    let featureImportances: [(name: String, importance: Double)]
    let factors: [PredictionFactor]       // detailed per-factor breakdown
    let engineType: String                // "bayesian" or "coreml" or "heuristic"
}

enum ActivityLevel: String, CaseIterable {
    case hot = "HOT"
    case active = "ACTIVE"
    case moderate = "MODERATE"
    case slow = "SLOW"
    case dead = "DEAD"

    var color: Color {
        switch self {
        case .hot: return Color(red: 0.1, green: 0.8, blue: 0.3)
        case .active: return Color(red: 0.2, green: 0.7, blue: 0.4)
        case .moderate: return Color(red: 1.0, green: 0.75, blue: 0.1)
        case .slow: return Color(red: 0.9, green: 0.45, blue: 0.15)
        case .dead: return Color(red: 0.6, green: 0.6, blue: 0.6)
        }
    }

    var icon: String {
        switch self {
        case .hot: return "flame.fill"
        case .active: return "bolt.fill"
        case .moderate: return "circle.fill"
        case .slow: return "tortoise.fill"
        case .dead: return "moon.zzz.fill"
        }
    }

    static func from(rating: Double) -> ActivityLevel {
        switch rating {
        case 4.5...5.0: return .hot
        case 3.5..<4.5: return .active
        case 2.5..<3.5: return .moderate
        case 1.5..<2.5: return .slow
        default: return .dead
        }
    }
}

// MARK: - Forecast Models

struct ForecastBlock: Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let conditions: EnvironmentalConditions
    let predictions: [UUID: VariablePrediction]  // keyed by TrackedVariable ID

    var timeRangeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "ha"
        return "\(f.string(from: startTime))-\(f.string(from: endTime))"
    }

    var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: startTime)
    }
}

struct ForecastDay: Identifiable {
    let id = UUID()
    let date: Date
    let blocks: [ForecastBlock]

    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
