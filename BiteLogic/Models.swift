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
    let windGustsMph: Double
    let waterTempF: Double
    let airTempF: Double
    let pressureHpa: Double
    let pressureChangeRate: Double
    let precipitationMm: Double
    let waveHeightM: Double
    let wavePeriodS: Double
    let cloudCoverPct: Double
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
    var precipitationMm: Double = 0       // mm in the period
    var waveHeightM: Double = 0           // significant wave height, meters
    var wavePeriodS: Double = 0           // dominant wave period, seconds
    var cloudCoverPct: Double = 0         // 0-100%
    var windGustsMph: Double = 0          // gust speed, mph
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
        let precipitation: [Double]?
        let cloudCover: [Double]?
        let windGusts10m: [Double]?
        enum CodingKeys: String, CodingKey {
            case time
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case temperature2m = "temperature_2m"
            case surfacePressure = "surface_pressure"
            case precipitation
            case cloudCover = "cloud_cover"
            case windGusts10m = "wind_gusts_10m"
        }
    }
}

struct MarineWeatherResponse: Codable {
    let hourly: MarineHourly
    struct MarineHourly: Codable {
        let time: [String]
        let seaSurfaceTemperature: [Double?]
        let waveHeight: [Double?]?
        let wavePeriod: [Double?]?
        enum CodingKeys: String, CodingKey {
            case time
            case seaSurfaceTemperature = "sea_surface_temperature"
            case waveHeight = "wave_height"
            case wavePeriod = "wave_period"
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

// MARK: - Species Profile
//
// Predefined species templates that drive temperature scoring and show
// seasonal activity multipliers. Users assign one to each tracked variable.

enum SpeciesProfile: String, Codable, CaseIterable {
    case generic       = "generic"
    case snook         = "snook"
    case tarpon        = "tarpon"
    case permit        = "permit"
    case redfish       = "redfish"
    case flounder      = "flounder"
    case speckledTrout = "speckled_trout"
    case bass          = "bass"
    case bluegill      = "bluegill"
    case walleye       = "walleye"

    var displayName: String {
        switch self {
        case .generic:       return "Generic"
        case .snook:         return "Snook"
        case .tarpon:        return "Tarpon"
        case .permit:        return "Permit"
        case .redfish:       return "Redfish"
        case .flounder:      return "Flounder"
        case .speckledTrout: return "Speckled Trout"
        case .bass:          return "Bass"
        case .bluegill:      return "Bluegill"
        case .walleye:       return "Walleye"
        }
    }

    var icon: String { "fish.fill" }

    // Comfortable temperature range (°F)
    var optimalTempMin: Double {
        switch self {
        case .generic:       return 62
        case .snook:         return 68
        case .tarpon:        return 74
        case .permit:        return 70
        case .redfish:       return 58
        case .flounder:      return 52
        case .speckledTrout: return 55
        case .bass:          return 58
        case .bluegill:      return 62
        case .walleye:       return 48
        }
    }

    var optimalTempMax: Double {
        switch self {
        case .generic:       return 84
        case .snook:         return 86
        case .tarpon:        return 90
        case .permit:        return 85
        case .redfish:       return 84
        case .flounder:      return 72
        case .speckledTrout: return 78
        case .bass:          return 80
        case .bluegill:      return 80
        case .walleye:       return 68
        }
    }

    /// Temperature score (0–1) for a given water temp using this species' preferred range.
    func tempScore(waterTempF: Double) -> Double {
        let mid  = (optimalTempMin + optimalTempMax) / 2.0
        let half = (optimalTempMax - optimalTempMin) / 2.0
        let dist = abs(waterTempF - mid)

        if dist <= half * 0.30 { return 0.95 }
        if dist <= half * 0.65 { return 0.80 }
        if dist <= half        { return 0.60 }
        // Outside optimal range — penalise progressively
        if waterTempF < optimalTempMin {
            return max(0.10, 0.60 - (optimalTempMin - waterTempF) * 0.035)
        } else {
            return max(0.10, 0.60 - (waterTempF - optimalTempMax) * 0.045)
        }
    }

    /// Seasonal activity multiplier (0–1) by month index (0 = January).
    var seasonalScores: [Double] {
        switch self {
        case .generic:
            return [0.60, 0.60, 0.70, 0.80, 0.90, 1.00, 1.00, 0.90, 0.90, 0.80, 0.70, 0.60]
        case .snook:
            return [0.30, 0.30, 0.50, 0.80, 1.00, 1.00, 0.90, 0.90, 1.00, 0.80, 0.50, 0.30]
        case .tarpon:
            return [0.20, 0.30, 0.50, 0.70, 0.90, 1.00, 1.00, 0.90, 0.80, 0.60, 0.30, 0.20]
        case .permit:
            return [0.40, 0.50, 0.70, 0.90, 1.00, 1.00, 0.80, 0.80, 0.90, 0.80, 0.60, 0.40]
        case .redfish:
            return [0.70, 0.70, 0.70, 0.80, 0.80, 0.70, 0.70, 0.80, 0.90, 1.00, 0.90, 0.80]
        case .flounder:
            return [0.60, 0.50, 0.70, 0.90, 0.80, 0.60, 0.60, 0.70, 0.90, 1.00, 0.80, 0.60]
        case .speckledTrout:
            return [0.70, 0.60, 0.80, 1.00, 0.90, 0.70, 0.70, 0.80, 0.90, 1.00, 0.90, 0.70]
        case .bass:
            return [0.60, 0.60, 0.90, 1.00, 0.90, 0.70, 0.60, 0.70, 0.80, 0.90, 0.70, 0.50]
        case .bluegill:
            return [0.40, 0.50, 0.70, 0.90, 1.00, 1.00, 0.90, 0.80, 0.70, 0.60, 0.40, 0.40]
        case .walleye:
            return [0.60, 0.70, 0.90, 1.00, 0.80, 0.60, 0.50, 0.60, 0.80, 1.00, 0.90, 0.70]
        }
    }

    /// Returns this month's seasonal score.
    func currentSeasonalScore() -> Double {
        let month = Calendar.current.component(.month, from: Date()) - 1
        return seasonalScores[month]
    }

    /// Human-readable description of temp preferences.
    var tempRangeDescription: String {
        "\(Int(optimalTempMin))–\(Int(optimalTempMax))°F"
    }

    /// Name of the current month's activity level.
    func currentSeasonLabel() -> String {
        let score = currentSeasonalScore()
        if score >= 0.90 { return "Peak season" }
        if score >= 0.70 { return "Active season" }
        if score >= 0.50 { return "Moderate season" }
        return "Off season"
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
    // Tide movement: false = no effect (landlocked), true = more movement is better
    var tideMovementEnabled: Bool = true
    // Time of day: nil = no effect, "night" = night better, "day" = day better
    var timePreference: String? = nil
    // Moon phase: nil = no effect, "new" = new moon better, "full" = full moon better
    var moonPreference: String? = nil
    // Tide stage: nil = no effect, "incoming" = incoming better, "outgoing" = outgoing better
    var tideStagePreference: String? = nil
    // Rain: nil = no effect, "norain" = no rain better, "rain" = rain better
    var rainPreference: String? = nil
    // Wave height: nil = no effect, "calmer" = calm better, "rougher" = rough better
    var wavePreference: String? = nil
    // Cloud cover: nil = no effect, "overcast" = overcast better, "sunny" = sunny better
    var cloudCoverPreference: String? = nil
    // Species profile: drives temperature scoring and shows seasonal context
    var speciesProfile: SpeciesProfile = .generic

    static let defaultPreferences = HeuristicPreferences()

    static func load(spotId: UUID? = nil) -> HeuristicPreferences {
        let key = prefsKey(for: spotId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let prefs = try? JSONDecoder().decode(HeuristicPreferences.self, from: data) else {
            return .defaultPreferences
        }
        return prefs
    }

    func save(spotId: UUID? = nil) {
        let key = Self.prefsKey(for: spotId)
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func weightsKey(for spotId: UUID?) -> String {
        guard let spotId else { return "heuristicWeights" }
        return "heuristicWeights_\(spotId.uuidString)"
    }

    static func loadWeights(spotId: UUID? = nil) -> [Double] {
        let key = weightsKey(for: spotId)
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Double].self, from: data),
           saved.count == HeuristicEngine.factorNames.count {
            return saved
        }
        return HeuristicEngine().weights
    }

    static func saveWeights(_ weights: [Double], spotId: UUID? = nil) {
        let key = weightsKey(for: spotId)
        if let data = try? JSONEncoder().encode(weights) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func prefsKey(for spotId: UUID?) -> String {
        guard let spotId else { return "heuristicPreferences" }
        return "heuristicPreferences_\(spotId.uuidString)"
    }

    // MARK: - Per-Variable Weights

    static func variableWeightsKey(for variableId: UUID) -> String {
        "heuristicWeights_var_\(variableId.uuidString)"
    }

    /// Returns nil if no variable-specific weights have been saved.
    static func loadVariableWeights(variableId: UUID) -> [Double]? {
        let key = variableWeightsKey(for: variableId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([Double].self, from: data),
              saved.count == HeuristicEngine.factorNames.count else { return nil }
        return saved
    }

    static func saveVariableWeights(_ weights: [Double], variableId: UUID) {
        let key = variableWeightsKey(for: variableId)
        if let data = try? JSONEncoder().encode(weights) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Per-Variable Preferences

    static func variablePrefsKey(for variableId: UUID) -> String {
        "heuristicPrefs_var_\(variableId.uuidString)"
    }

    static func loadVariablePreferences(variableId: UUID) -> HeuristicPreferences? {
        let key = variablePrefsKey(for: variableId)
        guard let data = UserDefaults.standard.data(forKey: key),
              let prefs = try? JSONDecoder().decode(HeuristicPreferences.self, from: data) else { return nil }
        return prefs
    }

    static func saveVariablePreferences(_ prefs: HeuristicPreferences, variableId: UUID) {
        let key = variablePrefsKey(for: variableId)
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: key)
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
    let displayValue: String  // actual reading shown on the bar, e.g. "12 mph", "78°F"

    static func colorForScore(_ score: Double) -> Color {
        if score >= 0.7 { return .green }
        if score >= 0.5 { return .orange }
        return .red   // gray is reserved for weight == 0 (unused factor)
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
