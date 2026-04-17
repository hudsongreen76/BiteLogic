import SwiftUI

// MARK: - Weight Settings View (Heuristic Engine Configuration)

struct WeightSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vm: FishingViewModel

    // Factor weights — loaded per-spot on appear
    @State private var weights: [Double] = HeuristicEngine().weights
    @State private var prefs: HeuristicPreferences = .defaultPreferences
    @State private var didLoad = false
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

                // All factors in one section
                Section("Factors") {
                    // Wind — direction is always clear
                    factorWeightRow(index: 0, description: "Less wind = better")
                    factorWeightRow(index: 5, description: "Dropping pressure = better")
                    factorWeightRow(index: 3, description: "Closer to 10-day avg = better")

                    // Tide Movement
                    prefPickerRow(
                        title: "Tide Movement", weightIndex: 1, defaultWeight: 0.25,
                        selectionBinding: Binding(
                            get: { prefs.tideMovementEnabled ? "more" : "none" },
                            set: { v in
                                prefs.tideMovementEnabled = v != "none"
                                if v == "none" { weights[1] = 0.0 } else if weights[1] == 0 { weights[1] = 0.25 }
                            }
                        ),
                        options: [("No Effect", "none"), ("More = Better", "more")]
                    )

                    // Time of Day
                    prefPickerRow(
                        title: "Time of Day", weightIndex: 2, defaultWeight: 0.15,
                        selectionBinding: Binding(
                            get: { prefs.timePreference ?? "none" },
                            set: { v in
                                prefs.timePreference = v == "none" ? nil : v
                                if v == "none" { weights[2] = 0.0 } else if weights[2] == 0 { weights[2] = 0.15 }
                            }
                        ),
                        options: [("No Effect", "none"), ("Night Better", "night"), ("Day Better", "day")]
                    )

                    // Moon Phase
                    prefPickerRow(
                        title: "Moon Phase", weightIndex: 4, defaultWeight: 0.10,
                        selectionBinding: Binding(
                            get: { prefs.moonPreference ?? "none" },
                            set: { v in
                                prefs.moonPreference = v == "none" ? nil : v
                                if v == "none" { weights[4] = 0.0 } else if weights[4] == 0 { weights[4] = 0.10 }
                            }
                        ),
                        options: [("No Effect", "none"), ("New Moon", "new"), ("Full Moon", "full")]
                    )

                    // Tide Stage
                    prefPickerRow(
                        title: "Tide Stage", weightIndex: 6, defaultWeight: 0.10,
                        selectionBinding: Binding(
                            get: { prefs.tideStagePreference ?? "none" },
                            set: { v in
                                prefs.tideStagePreference = v == "none" ? nil : v
                                if v == "none" { weights[6] = 0.0 } else if weights[6] == 0 { weights[6] = 0.10 }
                            }
                        ),
                        options: [("No Effect", "none"), ("Incoming", "incoming"), ("Outgoing", "outgoing")]
                    )

                    // Rain
                    prefPickerRow(
                        title: "Rain", weightIndex: 7, defaultWeight: 0.10,
                        selectionBinding: Binding(
                            get: { prefs.rainPreference ?? "none" },
                            set: { v in
                                prefs.rainPreference = v == "none" ? nil : v
                                if v == "none" { weights[7] = 0.0 } else if weights[7] == 0 { weights[7] = 0.10 }
                            }
                        ),
                        options: [("No Effect", "none"), ("No Rain Better", "norain"), ("Rain Better", "rain")]
                    )

                    // Wave Height
                    prefPickerRow(
                        title: "Wave Height", weightIndex: 8, defaultWeight: 0.10,
                        selectionBinding: Binding(
                            get: { prefs.wavePreference ?? "none" },
                            set: { v in
                                prefs.wavePreference = v == "none" ? nil : v
                                if v == "none" { weights[8] = 0.0 } else if weights[8] == 0 { weights[8] = 0.10 }
                            }
                        ),
                        options: [("No Effect", "none"), ("Calmer Better", "calmer"), ("Rougher Better", "rougher")]
                    )

                    // Cloud Cover
                    prefPickerRow(
                        title: "Cloud Cover", weightIndex: 9, defaultWeight: 0.10,
                        selectionBinding: Binding(
                            get: { prefs.cloudCoverPreference ?? "none" },
                            set: { v in
                                prefs.cloudCoverPreference = v == "none" ? nil : v
                                if v == "none" { weights[9] = 0.0 } else if weights[9] == 0 { weights[9] = 0.10 }
                            }
                        ),
                        options: [("No Effect", "none"), ("Overcast Better", "overcast"), ("Sunny Better", "sunny")]
                    )
                }

                Section {
                    Button("Reset All to Defaults") {
                        weights = [0.25, 0.25, 0.00, 0.15, 0.00, 0.25, 0.00, 0.00, 0.00, 0.00]
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
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                let spotId = vm.activeSpot?.id
                weights = HeuristicPreferences.loadWeights(spotId: spotId)
                prefs = HeuristicPreferences.load(spotId: spotId)
            }
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

    /// Row for factors that require a direction preference before activating.
    private func prefPickerRow(
        title: String,
        weightIndex: Int,
        defaultWeight: Double,
        selectionBinding: Binding<String>,
        options: [(label: String, tag: String)]
    ) -> some View {
        let active = selectionBinding.wrappedValue != "none"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if active {
                    Text(String(format: "%.0f%%", weights[weightIndex] * 100))
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                } else {
                    Text("Off")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Picker("", selection: selectionBinding) {
                ForEach(options, id: \.tag) { opt in
                    Text(opt.label).tag(opt.tag)
                }
            }
            .pickerStyle(.segmented)
            if active {
                Slider(value: $weights[weightIndex], in: 0.05...0.5, step: 0.05)
                    .tint(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Apply

    private func applySettings() {
        guard let spot = vm.activeSpot else { return }
        let spotId = spot.id ?? UUID()

        // Ensure direction-dependent factors with no preference have 0 weight
        if !prefs.tideMovementEnabled { weights[1] = 0 }
        if prefs.timePreference == nil { weights[2] = 0 }
        if prefs.moonPreference == nil { weights[4] = 0 }
        if prefs.tideStagePreference == nil { weights[6] = 0 }
        if prefs.rainPreference == nil { weights[7] = 0 }
        if prefs.wavePreference == nil { weights[8] = 0 }
        if prefs.cloudCoverPreference == nil { weights[9] = 0 }

        // Save per-spot
        prefs.save(spotId: spotId)
        HeuristicPreferences.saveWeights(weights, spotId: spotId)

        // Apply to all heuristic engines for this spot
        for variable in spot.sortedVariables {
            let varId = variable.id ?? UUID()
            let engine = PredictionManager.shared.heuristicEngine(for: spotId, variableId: varId)
            engine.weights = weights
            engine.preferences = prefs
        }
        PredictionManager.shared.updateHeuristicPreferences(prefs, spotId: spotId)
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
