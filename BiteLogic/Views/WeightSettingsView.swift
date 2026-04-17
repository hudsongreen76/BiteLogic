import SwiftUI

// MARK: - Weight Settings View (Heuristic Engine Configuration)

struct WeightSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vm: FishingViewModel

    // Factor weights
    @State private var weights: [Double] = {
        if let data = UserDefaults.standard.data(forKey: "heuristicWeights"),
           let saved = try? JSONDecoder().decode([Double].self, from: data),
           saved.count == HeuristicEngine.factorNames.count {
            return saved
        }
        return HeuristicEngine().weights
    }()

    // Heuristic preferences for optional factors
    @State private var prefs: HeuristicPreferences = .load()
    @State private var showingDebug = false

    private let factorNames = HeuristicEngine.factorNames

    var body: some View {
        NavigationView {
            List {
                // Mode info
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Default Prediction Settings")
                                .font(.subheadline.bold())
                            Text("Configure the assumptions used for the heuristic prediction engine.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Always-on factors (with weight sliders)
                Section("Always-On Factors") {
                    factorWeightRow(index: 0, description: "Less wind = better")
                    factorWeightRow(index: 1, description: "More tide movement = better")
                    factorWeightRow(index: 5, description: "Dropping pressure = better")
                    factorWeightRow(index: 3, description: "Closer to 10-day avg = better")
                }

                // Optional factors (user chooses preference or leaves off)
                Section("Optional Factors") {
                    Text("These factors have no effect by default. Set a preference to activate them.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Time of Day
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Time of Day")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if prefs.timePreference != nil {
                                Text(String(format: "%.0f%%", weights[2] * 100))
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                            }
                        }
                        Picker("Preference", selection: Binding(
                            get: { prefs.timePreference ?? "none" },
                            set: { prefs.timePreference = $0 == "none" ? nil : $0
                                   if $0 == "none" { weights[2] = 0.0 } else if weights[2] == 0 { weights[2] = 0.15 }
                            }
                        )) {
                            Text("No Effect").tag("none")
                            Text("Night is Better").tag("night")
                            Text("Day is Better").tag("day")
                        }
                        .pickerStyle(.segmented)
                        if prefs.timePreference != nil {
                            Slider(value: $weights[2], in: 0.05...0.5, step: 0.05)
                                .tint(.accentColor)
                        }
                    }
                    .padding(.vertical, 4)

                    // Moon Phase
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Moon Phase")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if prefs.moonPreference != nil {
                                Text(String(format: "%.0f%%", weights[4] * 100))
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                            }
                        }
                        Picker("Preference", selection: Binding(
                            get: { prefs.moonPreference ?? "none" },
                            set: { prefs.moonPreference = $0 == "none" ? nil : $0
                                   if $0 == "none" { weights[4] = 0.0 } else if weights[4] == 0 { weights[4] = 0.10 }
                            }
                        )) {
                            Text("No Effect").tag("none")
                            Text("New Moon Better").tag("new")
                            Text("Full Moon Better").tag("full")
                        }
                        .pickerStyle(.segmented)
                        if prefs.moonPreference != nil {
                            Slider(value: $weights[4], in: 0.05...0.5, step: 0.05)
                                .tint(.accentColor)
                        }
                    }
                    .padding(.vertical, 4)

                    // Tide Stage
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Tide Stage")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            if prefs.tideStagePreference != nil {
                                Text(String(format: "%.0f%%", weights[6] * 100))
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                            }
                        }
                        Picker("Preference", selection: Binding(
                            get: { prefs.tideStagePreference ?? "none" },
                            set: { prefs.tideStagePreference = $0 == "none" ? nil : $0
                                   if $0 == "none" { weights[6] = 0.0 } else if weights[6] == 0 { weights[6] = 0.10 }
                            }
                        )) {
                            Text("No Effect").tag("none")
                            Text("Incoming Better").tag("incoming")
                            Text("Outgoing Better").tag("outgoing")
                        }
                        .pickerStyle(.segmented)
                        if prefs.tideStagePreference != nil {
                            Slider(value: $weights[6], in: 0.05...0.5, step: 0.05)
                                .tint(.accentColor)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button("Reset All to Defaults") {
                        weights = [0.25, 0.25, 0.00, 0.15, 0.00, 0.25, 0.00]
                        prefs = .defaultPreferences
                    }
                    .foregroundColor(.orange)
                }

                // Engine status
                Section("Status") {
                    if let spot = vm.activeSpot {
                        let entries = spot.sortedLogEntries
                        LabeledContent("Logged Trips", value: "\(entries.count)")
                        LabeledContent("Mode", value: PredictionManager.shared.predictionMode.label)

                        if PredictionManager.shared.predictionMode == .learned {
                            if entries.count < 5 {
                                Text("Switch to Learned mode requires 5+ logged trips. Currently at \(entries.count).")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            } else {
                                Text("Bayesian regression active — learning from your data.")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }

                Section {
                    Button("Show Debug Info") { showingDebug = true }
                }
            }
            .navigationTitle("Default Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        applySettings()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingDebug) { debugView }
        }
    }

    // MARK: - Factor Weight Row

    private func factorWeightRow(index: Int, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(factorNames[index])
                        .font(.subheadline.weight(.medium))
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(String(format: "%.0f%%", weights[index] * 100))
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
            }
            Slider(value: $weights[index], in: 0...0.5, step: 0.05)
                .tint(colorForWeight(weights[index]))
        }
        .padding(.vertical, 2)
    }

    private func colorForWeight(_ w: Double) -> Color {
        if w >= 0.20 { return .green }
        if w >= 0.10 { return .orange }
        return .gray
    }

    // MARK: - Apply

    private func applySettings() {
        // Ensure optional factors with no preference have 0 weight
        if prefs.timePreference == nil { weights[2] = 0 }
        if prefs.moonPreference == nil { weights[4] = 0 }
        if prefs.tideStagePreference == nil { weights[6] = 0 }

        // Save preferences
        prefs.save()

        // Save weights
        if let data = try? JSONEncoder().encode(weights) {
            UserDefaults.standard.set(data, forKey: "heuristicWeights")
        }

        // Apply to all heuristic engines
        guard let spot = vm.activeSpot else { return }
        let spotId = spot.id ?? UUID()
        for variable in spot.sortedVariables {
            let varId = variable.id ?? UUID()
            let engine = PredictionManager.shared.heuristicEngine(for: spotId, variableId: varId)
            engine.weights = weights
            engine.preferences = prefs
        }
        PredictionManager.shared.updateHeuristicPreferences(prefs)
        vm.computePredictions()
    }

    // MARK: - Debug View

    private var debugView: some View {
        NavigationView {
            List {
                if let spot = vm.activeSpot {
                    let spotId = spot.id ?? UUID()
                    let entries = spot.sortedLogEntries

                    Section("Spot Info") {
                        LabeledContent("Name", value: spot.name ?? "Unknown")
                        LabeledContent("NOAA Station", value: spot.noaaStationId ?? "None")
                        LabeledContent("Coordinates", value: String(format: "%.4f, %.4f", spot.latitude, spot.longitude))
                        LabeledContent("Timezone", value: spot.timezone ?? "Unknown")
                        LabeledContent("Total Entries", value: "\(entries.count)")
                        LabeledContent("Mode", value: PredictionManager.shared.predictionMode.label)
                    }

                    ForEach(spot.sortedVariables, id: \.id) { variable in
                        let varId = variable.id ?? UUID()
                        Section("\(variable.name ?? "Unknown") - Debug") {
                            let weights = PredictionManager.shared.learnedWeights(for: spotId, variableId: varId)
                            if !weights.isEmpty && weights.contains(where: { $0.weight != 0 }) {
                                ForEach(weights, id: \.name) { w in
                                    HStack {
                                        Text(w.name).font(.system(size: 10))
                                        Spacer()
                                        Text(String(format: "%.6f", w.weight))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(w.weight > 0 ? .green : (w.weight < 0 ? .red : .secondary))
                                    }
                                }
                            } else {
                                Text("No learned weights yet (need 5+ entries in Learned mode)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let pred = vm.predictions[varId] {
                                LabeledContent("Current Rating", value: String(format: "%.2f", pred.predictedRating))
                                LabeledContent("Percentage", value: String(format: "%.0f%%", pred.percentage))
                                LabeledContent("Engine", value: pred.engineType)
                            }
                        }
                    }

                    let snapshots = entries.compactMap { $0.environmentalSnapshot }
                    if !snapshots.isEmpty {
                        Section("Avg Conditions (from logs)") {
                            let avgWind = snapshots.map(\.windMph).reduce(0, +) / Double(snapshots.count)
                            let avgWaterTemp = snapshots.map(\.waterTempF).reduce(0, +) / Double(snapshots.count)
                            let avgPressure = snapshots.map(\.pressureHpa).reduce(0, +) / Double(snapshots.count)
                            LabeledContent("Wind", value: String(format: "%.1f mph", avgWind))
                            LabeledContent("Water Temp", value: String(format: "%.1f°F", avgWaterTemp))
                            LabeledContent("Pressure", value: String(format: "%.1f hPa", avgPressure))
                        }
                    }
                }
            }
            .navigationTitle("Debug Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showingDebug = false }
                }
            }
        }
    }
}
