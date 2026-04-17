import Foundation
import CoreML
import CreateML
import TabularData

/// CoreML-based prediction engine using on-device training.
/// Available when 30+ entries exist. At 50+ offers boosted tree option.
class CoreMLEngine: PredictionEngineProtocol {
    private(set) var entryCount = 0
    private var model: MLModel?
    private var useBoostedTree: Bool
    private var rmse: Double?

    let spotId: UUID
    let variableId: UUID

    init(spotId: UUID, variableId: UUID, useBoostedTree: Bool = false) {
        self.spotId = spotId
        self.variableId = variableId
        self.useBoostedTree = useBoostedTree
        loadSavedModel()
    }

    // MARK: - PredictionEngineProtocol

    func predict(conditions: EnvironmentalConditions) -> VariablePrediction {
        guard let model = model else {
            return fallbackPrediction()
        }

        let features = FeatureExtractor.extract(from: conditions)
        let featureNames = FeatureExtractor.featureNames

        // Build MLFeatureProvider
        var dict: [String: MLFeatureValue] = [:]
        for (i, name) in featureNames.enumerated() {
            dict[name] = MLFeatureValue(double: features[i])
        }

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: dict)
            let result = try model.prediction(from: provider)
            let predicted = result.featureValue(for: "rating")?.doubleValue ?? 3.0
            let rating = min(5.0, max(1.0, predicted))

            // Approximate confidence from training RMSE
            let uncertainty = rmse ?? 1.0
            let ci = (low: max(1.0, rating - 1.96 * uncertainty),
                      high: min(5.0, rating + 1.96 * uncertainty))

            // Feature importances via perturbation (simplified)
            let importances = computeFeatureImportances(baseFeatures: features, baseRating: rating)

            let percentage = (rating - 1.0) / 4.0 * 100.0
            return VariablePrediction(
                predictedRating: rating,
                percentage: min(100, max(0, percentage)),
                confidenceInterval: ci,
                featureImportances: importances,
                factors: [],
                engineType: useBoostedTree ? "coreml-boosted" : "coreml-linear"
            )
        } catch {
            return fallbackPrediction()
        }
    }

    func updateWeights(entries: [(conditions: EnvironmentalConditions, rating: Double)]) {
        entryCount = entries.count
        guard entries.count >= 30 else { return }

        Task.detached { [weak self] in
            guard let self = self else { return }
            await self.trainModel(entries: entries)
        }
    }

    // MARK: - Training

    private func trainModel(entries: [(conditions: EnvironmentalConditions, rating: Double)]) async {
        let featureNames = FeatureExtractor.featureNames

        // Build DataFrame
        var columns: [String: [Double]] = [:]
        for name in featureNames {
            columns[name] = []
        }
        columns["rating"] = []

        for entry in entries {
            let features = FeatureExtractor.extract(from: entry.conditions)
            for (i, name) in featureNames.enumerated() {
                columns[name]?.append(features[i])
            }
            columns["rating"]?.append(entry.rating)
        }

        var dataFrame = DataFrame()
        for name in featureNames {
            dataFrame.append(column: Column<Double>(name: name, contents: columns[name]!))
        }
        dataFrame.append(column: Column<Double>(name: "rating", contents: columns["rating"]!))

        do {
            let trainedModel: MLModel
            let metrics: MLRegressorMetrics
            let tempURL = modelDirectory.appendingPathComponent("temp.mlmodel")

            if useBoostedTree && entries.count >= 50 {
                let params = MLBoostedTreeRegressor.ModelParameters(
                    validation: .split(strategy: .automatic)
                )
                let regressor = try MLBoostedTreeRegressor(
                    trainingData: dataFrame,
                    targetColumn: "rating",
                    featureColumns: featureNames,
                    parameters: params
                )
                trainedModel = regressor.model
                metrics = regressor.trainingMetrics
                try regressor.write(to: tempURL)
            } else {
                let params = MLLinearRegressor.ModelParameters(
                    validation: .split(strategy: .automatic)
                )
                let regressor = try MLLinearRegressor(
                    trainingData: dataFrame,
                    targetColumn: "rating",
                    featureColumns: featureNames,
                    parameters: params
                )
                trainedModel = regressor.model
                metrics = regressor.trainingMetrics
                try regressor.write(to: tempURL)
            }

            // Compile and save
            let compiled = try await MLModel.compileModel(at: tempURL)
            let dest = compiledModelURL
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: compiled, to: dest)
            try? FileManager.default.removeItem(at: tempURL)

            await MainActor.run {
                self.model = trainedModel
                self.rmse = metrics.rootMeanSquaredError
            }
        } catch {
            // Training failed - keep using previous model or fallback
        }
    }

    // MARK: - Feature Importances (perturbation-based)

    private func computeFeatureImportances(baseFeatures: [Double], baseRating: Double) -> [(name: String, importance: Double)] {
        guard let model = model else { return [] }
        let featureNames = FeatureExtractor.featureNames
        var importances: [(name: String, importance: Double)] = []

        for i in 0..<featureNames.count {
            var perturbed = baseFeatures
            perturbed[i] += 0.1  // small perturbation

            var dict: [String: MLFeatureValue] = [:]
            for (j, name) in featureNames.enumerated() {
                dict[name] = MLFeatureValue(double: perturbed[j])
            }

            if let provider = try? MLDictionaryFeatureProvider(dictionary: dict),
               let result = try? model.prediction(from: provider),
               let value = result.featureValue(for: "rating")?.doubleValue {
                let delta = abs(value - baseRating)
                importances.append((name: featureNames[i], importance: delta))
            } else {
                importances.append((name: featureNames[i], importance: 0))
            }
        }

        // Normalize
        let total = importances.map(\.importance).reduce(0, +)
        if total > 0 {
            importances = importances.map { (name: $0.name, importance: $0.importance / total) }
        }

        return importances.sorted { $0.importance > $1.importance }
    }

    // MARK: - Model Persistence

    private var modelDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("CoreMLModels/\(spotId.uuidString)/\(variableId.uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var modelURL: URL {
        modelDirectory.appendingPathComponent(useBoostedTree ? "boosted.mlmodel" : "linear.mlmodel")
    }

    private var compiledModelURL: URL {
        modelDirectory.appendingPathComponent(useBoostedTree ? "boosted.mlmodelc" : "linear.mlmodelc")
    }

    private func loadSavedModel() {
        let url = compiledModelURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        model = try? MLModel(contentsOf: url)
    }

    // MARK: - Fallback

    private func fallbackPrediction() -> VariablePrediction {
        VariablePrediction(
            predictedRating: 3.0,
            percentage: 50.0,
            confidenceInterval: (low: 1.5, high: 4.5),
            featureImportances: [],
            factors: [],
            engineType: "coreml-untrained"
        )
    }
}
