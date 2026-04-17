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

                            // Prediction accuracy — the key new metric
                            PredictionAccuracyCard(
                                entries: entries,
                                variableId: activeVarId,
                                spotId: spotId
                            )

                            // Recent trend: predicted vs actual over time
                            if entries.count >= 3 {
                                RecentTrendCard(entries: entries, variableId: activeVarId, spotId: spotId)
                            }

                            // Feature importance chart
                            if let pred = vm.predictions[activeVarId] {
                                FeatureImportanceCard(prediction: pred)
                            }

                            // Learned weights
                            LearnedWeightsCard(spotId: spotId, variableId: activeVarId)

                            // Rating distribution
                            RatingDistributionCard(entries: entries, variableId: activeVarId)

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
                    thresholdRow("Bayesian (5+ trips)", threshold: 5, current: entryCount, icon: "function")
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

// MARK: - Prediction Accuracy Card
//
// Retroactively runs the heuristic engine on each log entry's saved snapshot
// and compares predicted rating to the actual rating the user logged.
// Groups results into buckets to show calibration quality.

struct PredictionAccuracyCard: View {
    let entries: [LogEntryEntity]
    let variableId: UUID
    let spotId: UUID

    private struct AccuracyPoint {
        let predicted: Double
        let actual: Double
        var error: Double { abs(predicted - actual) }
    }

    private var points: [AccuracyPoint] {
        let engine = PredictionManager.shared.heuristicEngine(for: spotId, variableId: variableId)
        return entries.compactMap { entry -> AccuracyPoint? in
            guard let snapshot = entry.environmentalSnapshot,
                  let ratings = entry.ratings as? Set<VariableRatingEntity>,
                  let rating = ratings.first(where: { $0.variable?.id == variableId }) else {
                return nil
            }
            let pred = engine.predict(conditions: snapshot.toConditions)
            return AccuracyPoint(predicted: pred.predictedRating, actual: rating.ratingValue)
        }
    }

    private struct Bucket {
        let label: String
        let range: ClosedRange<Double>
        let color: Color
        var points: [AccuracyPoint] = []
        var avgActual: Double {
            guard !points.isEmpty else { return 0 }
            return points.map(\.actual).reduce(0, +) / Double(points.count)
        }
        var count: Int { points.count }
    }

    private var buckets: [Bucket] {
        var b: [Bucket] = [
            Bucket(label: "Poor (1–2)",     range: 1.0...2.49, color: .gray),
            Bucket(label: "Fair (2–3)",     range: 2.5...3.49, color: .orange),
            Bucket(label: "Good (3–4)",     range: 3.5...4.49, color: .blue),
            Bucket(label: "Excellent (4–5)", range: 4.5...5.0,  color: .green),
        ]
        for pt in points {
            for i in b.indices {
                if b[i].range.contains(pt.predicted) {
                    b[i].points.append(pt)
                    break
                }
            }
        }
        return b
    }

    private var meanAbsoluteError: Double {
        guard !points.isEmpty else { return 0 }
        return points.map(\.error).reduce(0, +) / Double(points.count)
    }

    private var calibrationScore: Double {
        // 0–100: lower MAE = higher score. MAE of 0 → 100, MAE of 2 → 0.
        max(0, min(100, (1.0 - meanAbsoluteError / 2.0) * 100))
    }

    var body: some View {
        CardView(title: "Prediction Accuracy", systemImage: "target") {
            if points.isEmpty {
                Text("Log trips with environmental snapshots to see accuracy data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // Summary metrics
                    HStack(spacing: 20) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f", calibrationScore))
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(scoreColor(calibrationScore))
                            Text("Accuracy Score")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        VStack(spacing: 2) {
                            Text(String(format: "±%.2f★", meanAbsoluteError))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                            Text("Avg Error")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        VStack(spacing: 2) {
                            Text("\(points.count)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("Trips")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    // Per-bucket breakdown
                    Text("WHEN APP PREDICTED...")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)

                    ForEach(buckets.filter { $0.count > 0 }, id: \.label) { bucket in
                        HStack(spacing: 8) {
                            Text(bucket.label)
                                .font(.caption)
                                .frame(width: 110, alignment: .leading)
                                .foregroundColor(bucket.color)

                            Text("avg actual:")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            starsView(rating: bucket.avgActual)

                            Text(String(format: "%.1f★", bucket.avgActual))
                                .font(.caption.bold())
                                .foregroundColor(.primary)

                            Spacer()

                            Text("(\(bucket.count))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("A well-calibrated app will show higher actual ratings when it predicts higher — use this to tune factor weights.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 { return .green }
        if score >= 50 { return .orange }
        return .red
    }

    @ViewBuilder
    private func starsView(rating: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= rating.rounded() ? "star.fill" : "star")
                    .font(.system(size: 8))
                    .foregroundColor(.yellow)
            }
        }
    }
}

// MARK: - Recent Trend Card
//
// Sparkline chart comparing what the app predicted vs what the user
// actually logged over the last N trips (newest on right).

struct RecentTrendCard: View {
    let entries: [LogEntryEntity]
    let variableId: UUID
    let spotId: UUID

    private struct TripPoint: Identifiable {
        let id = UUID()
        let date: Date
        let predicted: Double
        let actual: Double
    }

    private var trips: [TripPoint] {
        let engine = PredictionManager.shared.heuristicEngine(for: spotId, variableId: variableId)
        let sorted = entries.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        let recent = Array(sorted.suffix(20))   // last 20 trips max
        return recent.compactMap { entry -> TripPoint? in
            guard let snapshot = entry.environmentalSnapshot,
                  let date = entry.date,
                  let ratings = entry.ratings as? Set<VariableRatingEntity>,
                  let rating = ratings.first(where: { $0.variable?.id == variableId }) else { return nil }
            let pred = engine.predict(conditions: snapshot.toConditions)
            return TripPoint(date: date, predicted: pred.predictedRating, actual: rating.ratingValue)
        }
    }

    var body: some View {
        CardView(title: "Predicted vs Actual", systemImage: "chart.xyaxis.line") {
            if trips.count < 2 {
                Text("Log at least 2 trips to see the trend.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Legend
                    HStack(spacing: 16) {
                        legendDot(color: .green, label: "Predicted")
                        legendDot(color: .orange, label: "Actual")
                    }

                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        ZStack {
                            // Grid lines at 1, 2, 3, 4, 5
                            ForEach([1.0, 2.0, 3.0, 4.0, 5.0], id: \.self) { r in
                                let y = yPos(r, height: h)
                                Path { p in
                                    p.move(to: CGPoint(x: 0, y: y))
                                    p.addLine(to: CGPoint(x: w, y: y))
                                }
                                .stroke(Color(.systemGray5), lineWidth: 0.5)

                                Text("\(Int(r))★")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .position(x: 12, y: y)
                            }

                            // Predicted line
                            linePath(values: trips.map(\.predicted), width: w, height: h)
                                .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                            // Actual line
                            linePath(values: trips.map(\.actual), width: w, height: h)
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 3]))

                            // Dots for actuals
                            ForEach(Array(trips.enumerated()), id: \.element.id) { idx, trip in
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 5, height: 5)
                                    .position(x: xPos(idx, count: trips.count, width: w),
                                              y: yPos(trip.actual, height: h))
                            }
                        }
                    }
                    .frame(height: 130)

                    Text("Last \(trips.count) trips · newest on right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func xPos(_ idx: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return width / 2 }
        return CGFloat(idx) / CGFloat(count - 1) * width
    }

    private func yPos(_ rating: Double, height: CGFloat) -> CGFloat {
        let inset: CGFloat = 10
        let plotH = height - 2 * inset
        return inset + plotH - CGFloat((rating - 1) / 4.0) * plotH
    }

    private func linePath(values: [Double], width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            guard let first = values.first else { return }
            path.move(to: CGPoint(x: xPos(0, count: values.count, width: width),
                                  y: yPos(first, height: height)))
            for (i, v) in values.dropFirst().enumerated() {
                path.addLine(to: CGPoint(x: xPos(i + 1, count: values.count, width: width),
                                         y: yPos(v, height: height)))
            }
        }
    }

    @ViewBuilder
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }
}
