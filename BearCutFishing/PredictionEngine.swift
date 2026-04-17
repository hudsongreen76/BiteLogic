import Foundation
import Combine

// MARK: - Prediction Engine Protocol

protocol PredictionEngineProtocol {
    func predict(conditions: EnvironmentalConditions) -> VariablePrediction
    func updateWeights(entries: [(conditions: EnvironmentalConditions, rating: Double)])
    var entryCount: Int { get }
}

// MARK: - Feature Extraction

/// Extracts ~22 features from EnvironmentalConditions including interaction terms.
struct FeatureExtractor {

    static let featureNames: [String] = [
        "Wind Speed",
        "Wind Dir (sin)",
        "Wind Dir (cos)",
        "Tide Height",
        "Tide Change Rate",
        "Tide: Incoming",
        "Tide: Outgoing",
        "Tide: Slack",
        "Moon Phase",
        "Moon Illumination",
        "Water Temp",
        "Air Temp",
        "Pressure",
        "Pressure Change",
        "Time (sin)",
        "Time (cos)",
        "Is Daylight",
        // Interaction terms
        "Moon x Night",
        "Tide Stage x Wind",
        "Pressure Change x Tide Rate",
        "Daylight x Wind",
        "Bias"
    ]

    static var featureCount: Int { featureNames.count }

    /// Extract normalized feature vector from conditions.
    static func extract(from c: EnvironmentalConditions) -> [Double] {
        let windNorm = min(c.windMph / 30.0, 1.0)
        let windDirRad = c.windDirection * .pi / 180.0
        let windDirSin = sin(windDirRad)
        let windDirCos = cos(windDirRad)
        let tideHeight = c.tideHeight / 3.0
        let tideRate = c.tideChangeRate / 0.5
        let tideIncoming: Double = c.tideStage == .incoming ? 1.0 : 0.0
        let tideOutgoing: Double = c.tideStage == .outgoing ? 1.0 : 0.0
        let tideSlack: Double = c.tideStage == .slack ? 1.0 : 0.0
        let moonPhase = c.moonPhase
        let moonIllum = c.moonIllumination
        let waterTemp = (c.waterTempF - 60) / 30.0
        let airTemp = (c.airTempF - 60) / 30.0
        let pressure = (c.pressureHpa - 990) / 40.0
        let pressureChange = c.pressureChangeRate / 3.0
        let timeRad = c.timeOfDay / 24.0 * 2 * .pi
        let timeSin = sin(timeRad)
        let timeCos = cos(timeRad)
        let isDaylight: Double = c.isDaylight ? 1.0 : 0.0

        let moonXNight = moonPhase * (1.0 - isDaylight)
        let tideStageXWind = (tideIncoming - tideSlack) * windNorm
        let pressureXTide = pressureChange * tideRate
        let daylightXWind = isDaylight * windNorm

        let bias = 1.0

        return [
            windNorm, windDirSin, windDirCos,
            tideHeight, tideRate,
            tideIncoming, tideOutgoing, tideSlack,
            moonPhase, moonIllum,
            waterTemp, airTemp,
            pressure, pressureChange,
            timeSin, timeCos, isDaylight,
            moonXNight, tideStageXWind, pressureXTide, daylightXWind,
            bias
        ]
    }
}

// MARK: - Heuristic Engine (Default Predictions)
//
// Assumptions:
// - Wind: less is better
// - Tide movement: more is better
// - Time of day: NO EFFECT by default (user can pick night or day)
// - Water temp: closer to 10-day average is better
// - Moon phase: NO EFFECT by default (user can pick new or full)
// - Pressure: dropping is better
// - Tide stage: NO EFFECT by default (user can pick incoming or outgoing)

class HeuristicEngine: PredictionEngineProtocol {
    var entryCount: Int = 0

    /// Adjustable weights for each factor
    var weights: [Double] = [0.25, 0.25, 0.00, 0.15, 0.00, 0.25, 0.00]
    static let factorNames = ["Wind", "Tide Movement", "Time of Day", "Water Temp", "Moon Phase", "Pressure", "Tide Stage"]

    /// User preferences for optional factors
    var preferences: HeuristicPreferences = .load()

    /// Baseline water temp for "10-day average" concept. Updated from recent data.
    var baselineWaterTemp: Double = 78.0

    func predict(conditions: EnvironmentalConditions) -> VariablePrediction {
        let factorResults = detailedFactors(conditions)
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0.01 else {
            // All weights are zero — return neutral
            return VariablePrediction(
                predictedRating: 3.0,
                percentage: 50.0,
                confidenceInterval: (low: 1.5, high: 4.5),
                featureImportances: [],
                factors: factorResults,
                engineType: "heuristic"
            )
        }
        let raw = zip(factorResults.map(\.score), weights).map { $0.0 * $0.1 }.reduce(0, +) / totalWeight
        let percentage = raw * 100.0
        let rating = 1.0 + raw * 4.0

        return VariablePrediction(
            predictedRating: min(5, max(1, rating)),
            percentage: min(100, max(0, percentage)),
            confidenceInterval: (low: max(1, rating - 1.5), high: min(5, rating + 1.5)),
            featureImportances: factorResults.map { (name: $0.name, importance: $0.contribution) }
                .sorted { $0.importance > $1.importance },
            factors: factorResults,
            engineType: "heuristic"
        )
    }

    func updateWeights(entries: [(conditions: EnvironmentalConditions, rating: Double)]) {
        entryCount = entries.count
    }

    func detailedFactors(_ c: EnvironmentalConditions) -> [PredictionFactor] {
        let scores = scoreFactors(c)
        let notes = factorNotes(c)

        return zip(zip(Self.factorNames, scores), zip(weights, notes)).map { pair in
            let ((name, score), (weight, note)) = pair
            return PredictionFactor(
                name: name,
                score: score,
                weight: weight,
                contribution: score * weight,
                note: note,
                color: weight == 0 ? .gray : PredictionFactor.colorForScore(score)
            )
        }
    }

    private func scoreFactors(_ c: EnvironmentalConditions) -> [Double] {
        // Wind: less is better
        let wind: Double = switch c.windMph {
        case ..<5: 0.90
        case 5..<10: 0.75
        case 10..<15: 0.50
        case 15..<20: 0.25
        default: 0.10
        }

        // Tide movement: more is better
        let tideRate = abs(c.tideChangeRate)
        let tide: Double = switch tideRate {
        case ..<0.05: 0.25
        case 0.05..<0.15: 0.50
        case 0.15..<0.30: 0.80
        default: 0.70
        }

        // Time of day: depends on user preference
        let time: Double
        let hour = Int(c.timeOfDay)
        switch preferences.timePreference {
        case "night":
            time = switch hour {
            case 21...23, 0...2: 0.90
            case 3...5: 0.75
            case 19...20: 0.65
            case 6...7: 0.40
            default: 0.20
            }
        case "day":
            time = switch hour {
            case 6...9: 0.85
            case 10...14: 0.70
            case 15...18: 0.80
            case 19...20: 0.50
            default: 0.20
            }
        default:
            time = 0.50  // No effect — neutral score
        }

        // Water temp: closer to baseline (10-day avg) is better
        let tempDiff = abs(c.waterTempF - baselineWaterTemp)
        let temp: Double = switch tempDiff {
        case ..<2: 0.90
        case 2..<5: 0.70
        case 5..<8: 0.50
        case 8..<12: 0.30
        default: 0.15
        }

        // Moon phase: depends on user preference
        let moon: Double
        switch preferences.moonPreference {
        case "new":
            let distFromNew = min(c.moonPhase, 1.0 - c.moonPhase)
            moon = switch distFromNew {
            case ..<0.07: 0.90
            case 0.07..<0.15: 0.70
            case 0.15..<0.30: 0.50
            default: 0.30
            }
        case "full":
            let distFromFull = abs(c.moonPhase - 0.5)
            moon = switch distFromFull {
            case ..<0.07: 0.90
            case 0.07..<0.15: 0.70
            case 0.15..<0.30: 0.50
            default: 0.30
            }
        default:
            moon = 0.50  // No effect — neutral score
        }

        // Pressure: dropping is better
        let pressure: Double = switch c.pressureChangeRate {
        case ...(-1.0): 0.90
        case (-1.0)...(-0.5): 0.75
        case (-0.5)...(-0.1): 0.65
        case (-0.1)...0.1: 0.50
        case 0.1...0.5: 0.40
        default: 0.30
        }

        // Tide stage: depends on user preference
        let tideStage: Double
        switch preferences.tideStagePreference {
        case "incoming":
            tideStage = switch c.tideStage {
            case .incoming: 0.85
            case .outgoing: 0.45
            case .slack: 0.30
            }
        case "outgoing":
            tideStage = switch c.tideStage {
            case .incoming: 0.45
            case .outgoing: 0.85
            case .slack: 0.30
            }
        default:
            tideStage = 0.50  // No effect — neutral score
        }

        return [wind, tide, time, temp, moon, pressure, tideStage]
    }

    private func factorNotes(_ c: EnvironmentalConditions) -> [String] {
        // Wind
        let windNote: String = switch c.windMph {
        case ..<5: "Very calm — excellent conditions"
        case 5..<10: "Light breeze — good conditions"
        case 10..<15: "Moderate wind — acceptable"
        case 15..<20: "Windy — challenging conditions"
        default: "Strong wind — difficult conditions"
        }

        // Tide movement
        let tideRate = abs(c.tideChangeRate)
        let tideNote: String
        if tideRate < 0.05 {
            tideNote = "Minimal movement — slow bait flow"
        } else if tideRate < 0.15 {
            tideNote = "Moderate current — decent movement"
        } else {
            tideNote = "Strong current — good bait movement"
        }

        // Time
        let hour = Int(c.timeOfDay)
        let timeNote: String
        if preferences.timePreference == nil {
            timeNote = "No preference set — tap settings to choose"
        } else if preferences.timePreference == "night" {
            timeNote = switch hour {
            case 21...23, 0...5: "Night hours — your preferred window"
            case 19...20: "Dusk — transition period"
            default: "Daytime — outside preferred window"
            }
        } else {
            timeNote = switch hour {
            case 6...18: "Daytime — your preferred window"
            case 19...20: "Dusk — transition period"
            default: "Night — outside preferred window"
            }
        }

        // Water temp
        let tempDiff = c.waterTempF - baselineWaterTemp
        let tempNote: String
        if abs(tempDiff) < 2 {
            tempNote = String(format: "Near average (%.0f°F) — stable conditions", baselineWaterTemp)
        } else if tempDiff > 0 {
            tempNote = String(format: "%.0f°F above average — warmer than usual", tempDiff)
        } else {
            tempNote = String(format: "%.0f°F below average — cooler than usual", abs(tempDiff))
        }

        // Moon
        let moonData = MoonPhaseData.calculate(for: Date())
        let moonNote: String
        if preferences.moonPreference == nil {
            moonNote = "\(moonData.phaseName) — no preference set"
        } else {
            let preferred = preferences.moonPreference == "new" ? "new moon" : "full moon"
            moonNote = "\(moonData.phaseName) — you prefer \(preferred)"
        }

        // Pressure
        let pressureNote: String = switch c.pressureChangeRate {
        case ...(-1.0): "Dropping fast — fish actively feeding"
        case (-1.0)...(-0.5): "Dropping — increased activity likely"
        case (-0.5)...(-0.1): "Slight drop — favorable"
        case (-0.1)...0.1: "Stable pressure — normal conditions"
        case 0.1...0.5: "Rising slightly — decreasing activity"
        default: "Rising — fish settling down"
        }

        // Tide stage
        let stageNote: String
        if preferences.tideStagePreference == nil {
            stageNote = "\(c.tideStage.label) — no preference set"
        } else {
            let preferred = preferences.tideStagePreference == "incoming" ? "incoming" : "outgoing"
            stageNote = "\(c.tideStage.label) — you prefer \(preferred)"
        }

        return [windNote, tideNote, timeNote, tempNote, moonNote, pressureNote, stageNote]
    }
}

// MARK: - Bayesian Linear Regression Engine
//
// Pure data-driven — makes NO assumptions. Learns everything from user log data.
// Requires 5+ entries to produce predictions.

class BayesianEngine: PredictionEngineProtocol {
    private(set) var entryCount = 0

    // Bayesian parameters
    private let n = FeatureExtractor.featureCount
    private var precisionMatrix: [[Double]]
    private var weightedSum: [Double]
    private var meanWeights: [Double]
    private let noiseVariance: Double = 0.5
    private let priorPrecision: Double = 0.1

    init() {
        let n = FeatureExtractor.featureCount
        precisionMatrix = (0..<n).map { i in
            (0..<n).map { j in i == j ? 0.1 : 0.0 }
        }
        weightedSum = Array(repeating: 0.0, count: n)
        meanWeights = Array(repeating: 0.0, count: n)
    }

    func predict(conditions: EnvironmentalConditions) -> VariablePrediction {
        guard entryCount >= 5 else {
            // Not enough data — return a "needs more data" prediction
            return VariablePrediction(
                predictedRating: 3.0,
                percentage: 50.0,
                confidenceInterval: (low: 1.0, high: 5.0),
                featureImportances: [],
                factors: [],
                engineType: "learned (\(entryCount)/5 entries)"
            )
        }

        let features = FeatureExtractor.extract(from: conditions)

        let raw = zip(features, meanWeights).map(*).reduce(0, +)
        let rating = min(5.0, max(1.0, raw))

        var variance = noiseVariance
        for i in 0..<n {
            if precisionMatrix[i][i] > 1e-10 {
                variance += features[i] * features[i] / precisionMatrix[i][i]
            }
        }
        let stddev = sqrt(variance)
        let ci = (low: max(1.0, rating - 1.96 * stddev), high: min(5.0, rating + 1.96 * stddev))

        // Feature importances
        let contributions = (0..<n).map { i in abs(meanWeights[i] * features[i]) }
        let totalContrib = contributions.reduce(0, +)
        let importances: [(name: String, importance: Double)] = (0..<n).map { i in
            (name: FeatureExtractor.featureNames[i],
             importance: totalContrib > 0 ? contributions[i] / totalContrib : 0)
        }.sorted { $0.importance > $1.importance }

        let percentage = (rating - 1.0) / 4.0 * 100.0

        // Build factors from top feature importances (show what the model thinks matters)
        let topFeatures = importances.prefix(7)
        let factors: [PredictionFactor] = topFeatures.map { feat in
            PredictionFactor(
                name: feat.name,
                score: feat.importance,
                weight: 1.0,
                contribution: feat.importance,
                note: learnedFactorNote(feat.name, importance: feat.importance),
                color: PredictionFactor.colorForScore(feat.importance * 3) // scale up for visibility
            )
        }

        return VariablePrediction(
            predictedRating: rating,
            percentage: min(100, max(0, percentage)),
            confidenceInterval: ci,
            featureImportances: importances,
            factors: factors,
            engineType: "learned (\(entryCount) entries)"
        )
    }

    private func learnedFactorNote(_ name: String, importance: Double) -> String {
        let pct = String(format: "%.0f%%", importance * 100)
        return "\(pct) of prediction — learned from your data"
    }

    func updateWeights(entries: [(conditions: EnvironmentalConditions, rating: Double)]) {
        entryCount = entries.count
        guard entries.count >= 5 else { return }

        let m = entries.count

        var X: [[Double]] = []
        var y: [Double] = []
        for entry in entries {
            X.append(FeatureExtractor.extract(from: entry.conditions))
            y.append(entry.rating)
        }

        let invSigma2 = 1.0 / noiseVariance

        precisionMatrix = (0..<n).map { i in
            (0..<n).map { j in i == j ? priorPrecision : 0.0 }
        }
        weightedSum = Array(repeating: 0.0, count: n)

        for row in 0..<m {
            for i in 0..<n {
                weightedSum[i] += invSigma2 * X[row][i] * y[row]
                for j in 0..<n {
                    precisionMatrix[i][j] += invSigma2 * X[row][i] * X[row][j]
                }
            }
        }

        meanWeights = solveLinearSystem(precisionMatrix, weightedSum)
    }

    private func solveLinearSystem(_ A: [[Double]], _ b: [Double]) -> [Double] {
        let n = b.count
        var aug = A.enumerated().map { i, row in row + [b[i]] }

        for col in 0..<n {
            var maxRow = col
            for row in (col + 1)..<n {
                if abs(aug[row][col]) > abs(aug[maxRow][col]) {
                    maxRow = row
                }
            }
            aug.swapAt(col, maxRow)

            guard abs(aug[col][col]) > 1e-12 else { continue }

            for row in (col + 1)..<n {
                let factor = aug[row][col] / aug[col][col]
                for j in col...(n) {
                    aug[row][j] -= factor * aug[col][j]
                }
            }
        }

        var x = Array(repeating: 0.0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            guard abs(aug[row][row]) > 1e-12 else { continue }
            var sum = aug[row][n]
            for j in (row + 1)..<n {
                sum -= aug[row][j] * x[j]
            }
            x[row] = sum / aug[row][row]
        }
        return x
    }

    /// Access learned weights for debug/insights
    var learnedWeights: [(name: String, weight: Double)] {
        (0..<n).map { i in
            (name: FeatureExtractor.featureNames[i], weight: meanWeights[i])
        }
    }
}

// MARK: - Prediction Manager

@MainActor
class PredictionManager: ObservableObject {
    static let shared = PredictionManager()

    /// The active prediction mode — persisted in UserDefaults
    @Published var predictionMode: PredictionMode {
        didSet {
            UserDefaults.standard.set(predictionMode.rawValue, forKey: "predictionMode")
        }
    }

    @Published var coreMLEnabled: [UUID: [UUID: Bool]] = [:]
    @Published var useBoostedTree: [UUID: [UUID: Bool]] = [:]
    private var heuristicEngines: [UUID: [UUID: HeuristicEngine]] = [:]
    private var bayesianEngines: [UUID: [UUID: BayesianEngine]] = [:]
    private var coreMLEngines: [UUID: [UUID: CoreMLEngine]] = [:]

    init() {
        let saved = UserDefaults.standard.string(forKey: "predictionMode") ?? "heuristic"
        self.predictionMode = PredictionMode(rawValue: saved) ?? .heuristic
    }

    func heuristicEngine(for spotId: UUID, variableId: UUID) -> HeuristicEngine {
        if heuristicEngines[spotId] == nil { heuristicEngines[spotId] = [:] }
        if heuristicEngines[spotId]![variableId] == nil {
            let engine = HeuristicEngine()
            // Load saved weights
            if let data = UserDefaults.standard.data(forKey: "heuristicWeights"),
               let saved = try? JSONDecoder().decode([Double].self, from: data),
               saved.count == HeuristicEngine.factorNames.count {
                engine.weights = saved
            }
            engine.preferences = HeuristicPreferences.load()
            heuristicEngines[spotId]![variableId] = engine
        }
        return heuristicEngines[spotId]![variableId]!
    }

    func bayesianEngine(for spotId: UUID, variableId: UUID) -> BayesianEngine {
        if bayesianEngines[spotId] == nil { bayesianEngines[spotId] = [:] }
        if bayesianEngines[spotId]![variableId] == nil {
            bayesianEngines[spotId]![variableId] = BayesianEngine()
        }
        return bayesianEngines[spotId]![variableId]!
    }

    func coreMLEngine(for spotId: UUID, variableId: UUID) -> CoreMLEngine {
        if coreMLEngines[spotId] == nil { coreMLEngines[spotId] = [:] }
        let boosted = useBoostedTree[spotId]?[variableId] ?? false
        if coreMLEngines[spotId]![variableId] == nil {
            coreMLEngines[spotId]![variableId] = CoreMLEngine(spotId: spotId, variableId: variableId, useBoostedTree: boosted)
        }
        return coreMLEngines[spotId]![variableId]!
    }

    func isCoreMLEnabled(spotId: UUID, variableId: UUID) -> Bool {
        coreMLEnabled[spotId]?[variableId] ?? false
    }

    func toggleCoreML(spotId: UUID, variableId: UUID) {
        if coreMLEnabled[spotId] == nil { coreMLEnabled[spotId] = [:] }
        let current = coreMLEnabled[spotId]![variableId] ?? false
        coreMLEnabled[spotId]![variableId] = !current
    }

    func predict(conditions: EnvironmentalConditions, spotId: UUID, variableId: UUID) -> VariablePrediction {
        switch predictionMode {
        case .heuristic:
            return heuristicEngine(for: spotId, variableId: variableId).predict(conditions: conditions)
        case .learned:
            // CoreML > Bayesian
            if isCoreMLEnabled(spotId: spotId, variableId: variableId) {
                let engine = coreMLEngine(for: spotId, variableId: variableId)
                if engine.entryCount >= 30 {
                    return engine.predict(conditions: conditions)
                }
            }
            return bayesianEngine(for: spotId, variableId: variableId).predict(conditions: conditions)
        }
    }

    func retrain(entries: [(conditions: EnvironmentalConditions, rating: Double)], spotId: UUID, variableId: UUID) {
        let bayesian = bayesianEngine(for: spotId, variableId: variableId)
        bayesian.updateWeights(entries: entries)

        let heuristic = heuristicEngine(for: spotId, variableId: variableId)
        heuristic.entryCount = entries.count

        if entries.count >= 30 {
            let coreml = coreMLEngine(for: spotId, variableId: variableId)
            coreml.updateWeights(entries: entries)
        }
    }

    func entryCount(for spotId: UUID, variableId: UUID) -> Int {
        bayesianEngine(for: spotId, variableId: variableId).entryCount
    }

    func canUseCoreML(for spotId: UUID, variableId: UUID) -> Bool {
        entryCount(for: spotId, variableId: variableId) >= 30
    }

    func canUseBoostedTree(for spotId: UUID, variableId: UUID) -> Bool {
        entryCount(for: spotId, variableId: variableId) >= 50
    }

    func learnedWeights(for spotId: UUID, variableId: UUID) -> [(name: String, weight: Double)] {
        bayesianEngine(for: spotId, variableId: variableId).learnedWeights
    }

    func activeEngineType(for spotId: UUID, variableId: UUID) -> String {
        switch predictionMode {
        case .heuristic:
            return "Default (Heuristic)"
        case .learned:
            if isCoreMLEnabled(spotId: spotId, variableId: variableId) && canUseCoreML(for: spotId, variableId: variableId) {
                return useBoostedTree[spotId]?[variableId] == true ? "CoreML (Boosted Tree)" : "CoreML (Linear)"
            }
            let count = entryCount(for: spotId, variableId: variableId)
            return count < 5 ? "Learned (need \(5 - count) more entries)" : "Bayesian (\(count) entries)"
        }
    }

    /// Update heuristic preferences across all engines
    func updateHeuristicPreferences(_ prefs: HeuristicPreferences) {
        prefs.save()
        for (_, varEngines) in heuristicEngines {
            for (_, engine) in varEngines {
                engine.preferences = prefs
            }
        }
    }

    /// Update baseline water temp for heuristic engines
    func updateBaselineWaterTemp(_ temp: Double, spotId: UUID) {
        guard let engines = heuristicEngines[spotId] else { return }
        for (_, engine) in engines {
            engine.baselineWaterTemp = temp
        }
    }
}
