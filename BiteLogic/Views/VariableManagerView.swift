import SwiftUI
import CoreData

// MARK: - Variable Manager

struct VariableManagerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    let spot: FishingSpotEntity

    @State private var showingAddSheet = false

    var sortedVariables: [TrackedVariableEntity] {
        spot.sortedVariables
    }

    var body: some View {
        List {
            ForEach(sortedVariables, id: \.id) { variable in
                NavigationLink {
                    VariableWeightEditorView(variable: variable, spot: spot)
                } label: {
                    variableRow(variable)
                }
            }
            .onDelete(perform: deleteVariables)
        }
        .navigationTitle("Tracked Variables")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddVariableSheet(spot: spot)
        }
    }

    @ViewBuilder
    private func variableRow(_ variable: TrackedVariableEntity) -> some View {
        let hasCustomWeights = variable.id.flatMap {
            HeuristicPreferences.loadVariableWeights(variableId: $0)
        } != nil
        let speciesProfile: SpeciesProfile? = variable.id.flatMap {
            HeuristicPreferences.loadVariablePreferences(variableId: $0)
        }.flatMap { prefs in prefs.speciesProfile != .generic ? prefs.speciesProfile : nil }

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(variable.name ?? "Unknown")
                    .font(.body)
                HStack(spacing: 4) {
                    Text(variable.type == VariableType.stars.rawValue ? "Stars (1–5)" : "Category")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let sp = speciesProfile {
                        Text(sp.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
            }
            Spacer()
            HStack(spacing: 6) {
                if hasCustomWeights {
                    Text("Custom")
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(6)
                }
                if variable.isDefault {
                    Text("Default")
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(6)
                }
            }
        }
    }

    private func deleteVariables(at offsets: IndexSet) {
        let vars = sortedVariables
        for idx in offsets {
            let v = vars[idx]
            if !v.isDefault {
                viewContext.delete(v)
            }
        }
        try? viewContext.save()
    }
}

// MARK: - Variable Weight Editor

struct VariableWeightEditorView: View {
    let variable: TrackedVariableEntity
    let spot: FishingSpotEntity

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: FishingViewModel

    @State private var weights: [Double] = HeuristicEngine().weights
    @State private var prefs: HeuristicPreferences = .defaultPreferences
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                Text("These weights only apply to \(variable.name ?? "this variable"). Other variables use their own settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Species Profile") {
                SpeciesPickerRow(profile: $prefs.speciesProfile)
            }

            Section("Factor Weights") {
                FactorWeightsSection(weights: $weights, prefs: $prefs)
            }

            Section {
                Button("Reset to Defaults") {
                    weights = HeuristicEngine().weights
                    prefs = .defaultPreferences
                }
                .foregroundColor(.orange)
            }
        }
        .navigationTitle(variable.name ?? "Variable")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            guard let varId = variable.id else { return }
            weights = HeuristicPreferences.loadVariableWeights(variableId: varId)
                ?? HeuristicPreferences.loadWeights(spotId: spot.id)
            prefs = HeuristicPreferences.loadVariablePreferences(variableId: varId)
                ?? HeuristicPreferences.load(spotId: spot.id)
        }
    }

    private func save() {
        guard let varId = variable.id, let spotId = spot.id else { return }

        var w = weights
        if !prefs.tideMovementEnabled { w[1] = 0 }
        if prefs.timePreference == nil   { w[2] = 0 }
        if prefs.moonPreference == nil   { w[4] = 0 }
        if prefs.tideStagePreference == nil { w[6] = 0 }
        if prefs.rainPreference == nil   { w[7] = 0 }
        if prefs.wavePreference == nil   { w[8] = 0 }
        if prefs.cloudCoverPreference == nil { w[9] = 0 }

        HeuristicPreferences.saveVariableWeights(w, variableId: varId)
        HeuristicPreferences.saveVariablePreferences(prefs, variableId: varId)

        // Invalidate cached engine so it reloads on next prediction
        let engine = PredictionManager.shared.heuristicEngine(for: spotId, variableId: varId)
        engine.weights = w
        engine.preferences = prefs
        vm.computePredictions()
    }
}

// MARK: - Species Picker Row

struct SpeciesPickerRow: View {
    @Binding var profile: SpeciesProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Species", selection: $profile) {
                ForEach(SpeciesProfile.allCases, id: \.rawValue) { sp in
                    Text(sp.displayName).tag(sp)
                }
            }

            if profile != .generic {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "thermometer")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Optimal temp: \(profile.tempRangeDescription)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(profile.currentSeasonLabel())
                            .font(.caption)
                            .foregroundColor(seasonColor(profile.currentSeasonalScore()))
                    }
                }
            } else {
                Text("Temperature scored relative to your 10-day average.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func seasonColor(_ score: Double) -> Color {
        if score >= 0.9 { return .green }
        if score >= 0.7 { return .orange }
        return .secondary
    }
}

// MARK: - Shared Factor Weights Section

/// Drop-in rows for a Form Section — shared by VariableWeightEditorView and AddVariableSheet.
struct FactorWeightsSection: View {
    @Binding var weights: [Double]
    @Binding var prefs: HeuristicPreferences

    private let names = HeuristicEngine.factorNames

    var body: some View {
        Group {
            // Always-directional
            alwaysOnRow(index: 0, description: "Less wind = better")
            alwaysOnRow(index: 5, description: "Dropping = better")
            alwaysOnRow(index: 3, description: "Near 10-day avg = better")

            // Direction-preference rows
            prefRow(
                title: "Tide Movement", index: 1, defaultWeight: 0.25,
                selection: Binding(
                    get: { prefs.tideMovementEnabled ? "more" : "none" },
                    set: { v in
                        prefs.tideMovementEnabled = v != "none"
                        if v == "none" { weights[1] = 0 } else if weights[1] == 0 { weights[1] = 0.25 }
                    }),
                options: [("No Effect", "none"), ("More = Better", "more")]
            )
            prefRow(
                title: "Time of Day", index: 2, defaultWeight: 0.15,
                selection: Binding(
                    get: { prefs.timePreference ?? "none" },
                    set: { v in
                        prefs.timePreference = v == "none" ? nil : v
                        if v == "none" { weights[2] = 0 } else if weights[2] == 0 { weights[2] = 0.15 }
                    }),
                options: [("No Effect", "none"), ("Night Better", "night"), ("Day Better", "day")]
            )
            prefRow(
                title: "Moon Phase", index: 4, defaultWeight: 0.10,
                selection: Binding(
                    get: { prefs.moonPreference ?? "none" },
                    set: { v in
                        prefs.moonPreference = v == "none" ? nil : v
                        if v == "none" { weights[4] = 0 } else if weights[4] == 0 { weights[4] = 0.10 }
                    }),
                options: [("No Effect", "none"), ("New Moon", "new"), ("Full Moon", "full")]
            )
            prefRow(
                title: "Tide Stage", index: 6, defaultWeight: 0.10,
                selection: Binding(
                    get: { prefs.tideStagePreference ?? "none" },
                    set: { v in
                        prefs.tideStagePreference = v == "none" ? nil : v
                        if v == "none" { weights[6] = 0 } else if weights[6] == 0 { weights[6] = 0.10 }
                    }),
                options: [("No Effect", "none"), ("Incoming", "incoming"), ("Outgoing", "outgoing")]
            )
            prefRow(
                title: "Rain", index: 7, defaultWeight: 0.10,
                selection: Binding(
                    get: { prefs.rainPreference ?? "none" },
                    set: { v in
                        prefs.rainPreference = v == "none" ? nil : v
                        if v == "none" { weights[7] = 0 } else if weights[7] == 0 { weights[7] = 0.10 }
                    }),
                options: [("No Effect", "none"), ("No Rain Better", "norain"), ("Rain Better", "rain")]
            )
            prefRow(
                title: "Wave Height", index: 8, defaultWeight: 0.10,
                selection: Binding(
                    get: { prefs.wavePreference ?? "none" },
                    set: { v in
                        prefs.wavePreference = v == "none" ? nil : v
                        if v == "none" { weights[8] = 0 } else if weights[8] == 0 { weights[8] = 0.10 }
                    }),
                options: [("No Effect", "none"), ("Calmer Better", "calmer"), ("Rougher Better", "rougher")]
            )
            prefRow(
                title: "Cloud Cover", index: 9, defaultWeight: 0.10,
                selection: Binding(
                    get: { prefs.cloudCoverPreference ?? "none" },
                    set: { v in
                        prefs.cloudCoverPreference = v == "none" ? nil : v
                        if v == "none" { weights[9] = 0 } else if weights[9] == 0 { weights[9] = 0.10 }
                    }),
                options: [("No Effect", "none"), ("Overcast Better", "overcast"), ("Sunny Better", "sunny")]
            )
        }
    }

    @ViewBuilder
    private func alwaysOnRow(index: Int, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(names[index])
                        .font(.subheadline.weight(.medium))
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(String(format: "%.0f%%", weights[index] * 100))
                    .font(.caption.bold())
                    .foregroundColor(weights[index] == 0 ? .gray : .accentColor)
            }
            Slider(value: $weights[index], in: 0...0.5, step: 0.05)
                .tint(weights[index] == 0 ? .gray : .accentColor)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func prefRow(
        title: String,
        index: Int,
        defaultWeight: Double,
        selection: Binding<String>,
        options: [(label: String, tag: String)]
    ) -> some View {
        let active = selection.wrappedValue != "none"
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if active {
                    Text(String(format: "%.0f%%", weights[index] * 100))
                        .font(.caption.bold())
                        .foregroundColor(.accentColor)
                } else {
                    Text("Off")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Picker("", selection: selection) {
                ForEach(options, id: \.tag) { opt in
                    Text(opt.label).tag(opt.tag)
                }
            }
            .pickerStyle(.segmented)
            if active {
                Slider(value: $weights[index], in: 0.05...0.5, step: 0.05)
                    .tint(.accentColor)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Variable Sheet

struct AddVariableSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let spot: FishingSpotEntity

    @State private var name = ""
    @State private var variableType: VariableType = .stars
    @State private var categoryOptions = ""
    @State private var weights: [Double] = HeuristicEngine().weights
    @State private var prefs: HeuristicPreferences = .defaultPreferences

    var body: some View {
        NavigationView {
            Form {
                Section("Variable Info") {
                    TextField("Variable Name", text: $name)
                    Picker("Type", selection: $variableType) {
                        Text("Stars (1–5)").tag(VariableType.stars)
                        Text("Category").tag(VariableType.category)
                    }
                    if variableType == .category {
                        TextField("Options (comma-separated)", text: $categoryOptions)
                            .font(.caption)
                    }
                }

                Section("Species Profile") {
                    SpeciesPickerRow(profile: $prefs.speciesProfile)
                }

                Section("Factor Weights") {
                    FactorWeightsSection(weights: $weights, prefs: $prefs)
                }

                Section {
                    Button("Add Variable") {
                        addVariable()
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty)
                }
            }
            .navigationTitle("New Variable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Seed from spot defaults
                weights = HeuristicPreferences.loadWeights(spotId: spot.id)
                prefs = HeuristicPreferences.load(spotId: spot.id)
            }
        }
    }

    private func addVariable() {
        let v = TrackedVariableEntity(context: viewContext)
        let newId = UUID()
        v.id = newId
        v.name = name
        v.type = variableType.rawValue
        v.isDefault = false
        v.sortOrder = Int16(spot.sortedVariables.count)
        v.spot = spot
        if variableType == .category && !categoryOptions.isEmpty {
            v.categoryOptions = categoryOptions
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) } as NSArray
        }
        try? viewContext.save()

        // Enforce zero weight for inactive preference factors
        var w = weights
        if !prefs.tideMovementEnabled  { w[1] = 0 }
        if prefs.timePreference == nil  { w[2] = 0 }
        if prefs.moonPreference == nil  { w[4] = 0 }
        if prefs.tideStagePreference == nil { w[6] = 0 }
        if prefs.rainPreference == nil  { w[7] = 0 }
        if prefs.wavePreference == nil  { w[8] = 0 }
        if prefs.cloudCoverPreference == nil { w[9] = 0 }

        HeuristicPreferences.saveVariableWeights(w, variableId: newId)
        HeuristicPreferences.saveVariablePreferences(prefs, variableId: newId)
    }
}
