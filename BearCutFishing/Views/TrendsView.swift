import SwiftUI
import CoreData

// MARK: - Insights View

struct InsightsView: View {
    @EnvironmentObject var vm: FishingViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedVariableId: UUID?
    @State private var showingWeightDebug = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if let spot = vm.activeSpot {
                        let variables = spot.sortedVariables
                        let entries = spot.sortedLogEntries

                        if entries.isEmpty {
                            emptyState
                        } else {
                            // Variable picker
                            if variables.count > 1 {
                                variablePicker(variables: variables)
                            }

                            let activeVarId = selectedVariableId ?? variables.first?.id ?? UUID()
                            let spotId = spot.id ?? UUID()

                            // Engine status
                            EngineStatusCard(spotId: spotId, variableId: activeVarId, entryCount: entries.count)

                            // Feature importance chart
                            if let pred = vm.predictions[activeVarId] {
                                FeatureImportanceCard(prediction: pred)
                            }

                            // Learned weights
                            LearnedWeightsCard(spotId: spotId, variableId: activeVarId)

                            // Rating distribution
                            RatingDistributionCard(entries: entries, variableId: activeVarId)

                            // CoreML toggle
                            if PredictionManager.shared.canUseCoreML(for: spotId, variableId: activeVarId) {
                                CoreMLToggleCard(spotId: spotId, variableId: activeVarId)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingWeightDebug = true
                    } label: {
                        Image(systemName: "ladybug")
                    }
                }
            }
            .sheet(isPresented: $showingWeightDebug) {
                WeightSettingsView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Log at least one trip to see insights.")
                .foregroundColor(.secondary)
        }
        .padding(.top, 40)
    }

    private func variablePicker(variables: [TrackedVariableEntity]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(variables, id: \.id) { v in
                    let isSelected = (selectedVariableId ?? variables.first?.id) == v.id
                    Button {
                        selectedVariableId = v.id
                    } label: {
                        Text(v.name ?? "Unknown")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
}

// MARK: - Engine Status Card

struct EngineStatusCard: View {
    let spotId: UUID
    let variableId: UUID
    let entryCount: Int

    var body: some View {
        CardView(title: "Prediction Engine", systemImage: "brain") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Active Engine:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(PredictionManager.shared.activeEngineType(for: spotId, variableId: variableId))
                        .font(.caption.bold())
                }

                HStack {
                    Text("Entries:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(entryCount)")
                        .font(.caption.bold())
                }

                // Progress bars for thresholds
                VStack(spacing: 4) {
                    thresholdRow("Heuristic", threshold: 0, current: entryCount, icon: "gearshape")
                    thresholdRow("Bayesian", threshold: 5, current: entryCount, icon: "function")
                    thresholdRow("CoreML (Linear)", threshold: 30, current: entryCount, icon: "cpu")
                    thresholdRow("CoreML (Boosted)", threshold: 50, current: entryCount, icon: "bolt.fill")
                }
            }
        }
    }

    private func thresholdRow(_ label: String, threshold: Int, current: Int, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(current >= threshold ? .green : .secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 10))
                .frame(width: 95, alignment: .leading)
            ProgressView(value: Double(min(current, threshold)), total: Double(max(threshold, 1)))
                .tint(current >= threshold ? .green : .orange)
            Text(current >= threshold ? "Ready" : "\(threshold - current) more")
                .font(.system(size: 9))
                .foregroundColor(current >= threshold ? .green : .secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

// MARK: - Feature Importance Card

struct FeatureImportanceCard: View {
    let prediction: VariablePrediction

    var body: some View {
        CardView(title: "Feature Importance", systemImage: "chart.bar.fill") {
            VStack(spacing: 6) {
                ForEach(prediction.featureImportances.prefix(8), id: \.name) { feature in
                    HStack(spacing: 8) {
                        Text(feature.name)
                            .font(.system(size: 10))
                            .frame(width: 110, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.systemGray5))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(barColor(for: feature.importance))
                                    .frame(width: max(2, geo.size.width * CGFloat(feature.importance)))
                            }
                        }
                        .frame(height: 12)
                        Text(String(format: "%.0f%%", feature.importance * 100))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func barColor(for importance: Double) -> Color {
        if importance > 0.2 { return .green }
        if importance > 0.1 { return .orange }
        return .gray
    }
}

// MARK: - Learned Weights Card

struct LearnedWeightsCard: View {
    let spotId: UUID
    let variableId: UUID
    @State private var isExpanded = false

    var weights: [(name: String, weight: Double)] {
        PredictionManager.shared.learnedWeights(for: spotId, variableId: variableId)
    }

    var body: some View {
        CardView(title: "Learned Weights", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    HStack {
                        Text(isExpanded ? "Hide raw weights" : "Show raw weights")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }

                if isExpanded {
                    // Interaction effects highlight
                    let interactionWeights = weights.filter { $0.name.contains("x") || $0.name.contains("X") }
                    if !interactionWeights.isEmpty {
                        Text("Interaction Effects:")
                            .font(.caption.bold())
                            .padding(.top, 4)
                        ForEach(interactionWeights, id: \.name) { w in
                            HStack {
                                Text(w.name)
                                    .font(.system(size: 10))
                                Spacer()
                                Text(String(format: "%.4f", w.weight))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(w.weight > 0 ? .green : (w.weight < 0 ? .red : .secondary))
                            }
                        }
                    }

                    Divider()

                    Text("All Weights:")
                        .font(.caption.bold())
                        .padding(.top, 4)
                    ForEach(weights, id: \.name) { w in
                        HStack {
                            Text(w.name)
                                .font(.system(size: 10))
                            Spacer()
                            Text(String(format: "%.4f", w.weight))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(w.weight > 0 ? .green : (w.weight < 0 ? .red : .secondary))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Rating Distribution

struct RatingDistributionCard: View {
    let entries: [LogEntryEntity]
    let variableId: UUID

    var body: some View {
        CardView(title: "Rating Distribution", systemImage: "chart.bar.fill") {
            VStack(spacing: 8) {
                ForEach(1...5, id: \.self) { rating in
                    let count = countForRating(rating)
                    let total = entries.count
                    let pct = total == 0 ? 0 : Double(count) / Double(total)
                    HStack {
                        HStack(spacing: 2) {
                            ForEach(1...rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.yellow)
                            }
                        }
                        .frame(width: 50, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor)
                                    .frame(width: geo.size.width * CGFloat(pct))
                            }
                        }
                        .frame(height: 18)

                        Text("\(count)")
                            .font(.caption.bold())
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func countForRating(_ target: Int) -> Int {
        entries.filter { entry in
            let ratings = (entry.ratings as? Set<VariableRatingEntity>) ?? []
            return ratings.contains { $0.variable?.id == variableId && Int($0.ratingValue.rounded()) == target }
        }.count
    }
}

// MARK: - CoreML Toggle Card

struct CoreMLToggleCard: View {
    let spotId: UUID
    let variableId: UUID

    var body: some View {
        CardView(title: "CoreML Engine", systemImage: "cpu") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Use CoreML Predictions", isOn: Binding(
                    get: { PredictionManager.shared.isCoreMLEnabled(spotId: spotId, variableId: variableId) },
                    set: { _ in PredictionManager.shared.toggleCoreML(spotId: spotId, variableId: variableId) }
                ))
                .font(.subheadline)

                if PredictionManager.shared.canUseBoostedTree(for: spotId, variableId: variableId) {
                    Text("50+ entries: Boosted Tree option available")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Text("CoreML trains an on-device model using your log data. It may capture non-linear patterns that Bayesian regression misses.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
