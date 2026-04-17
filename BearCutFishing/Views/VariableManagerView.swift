import SwiftUI
import CoreData

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
                HStack {
                    VStack(alignment: .leading) {
                        Text(variable.name ?? "Unknown")
                            .font(.body)
                        Text(variable.type == VariableType.stars.rawValue ? "Stars (1-5)" : "Category")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if variable.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(6)
                    }
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

    private func deleteVariables(at offsets: IndexSet) {
        let vars = sortedVariables
        for idx in offsets {
            let variable = vars[idx]
            if !variable.isDefault {
                viewContext.delete(variable)
            }
        }
        try? viewContext.save()
    }
}

// MARK: - Add Variable Sheet

struct AddVariableSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    let spot: FishingSpotEntity

    @State private var selectedPreset: String?
    @State private var customName = ""
    @State private var variableType: VariableType = .stars
    @State private var categoryOptions = ""

    private let presets: [(name: String, type: VariableType, categories: String)] = [
        ("Position", .category, "Bridge,Flats,Channel,Jetty,Mangroves,Open Water"),
        ("Top Water Bite", .stars, ""),
        ("Bottom Bite", .stars, ""),
        ("Bait Activity", .stars, ""),
        ("Current Strength", .stars, ""),
    ]

    var body: some View {
        NavigationView {
            Form {
                Section("Presets") {
                    ForEach(presets, id: \.name) { preset in
                        Button {
                            addPreset(preset)
                            dismiss()
                        } label: {
                            HStack {
                                Text(preset.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(preset.type == .stars ? "Stars" : "Category")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }

                Section("Custom Variable") {
                    TextField("Variable Name", text: $customName)
                    Picker("Type", selection: $variableType) {
                        Text("Stars (1-5)").tag(VariableType.stars)
                        Text("Category").tag(VariableType.category)
                    }
                    if variableType == .category {
                        TextField("Options (comma-separated)", text: $categoryOptions)
                            .font(.caption)
                    }
                    Button("Add Custom Variable") {
                        addCustom()
                        dismiss()
                    }
                    .disabled(customName.isEmpty)
                }
            }
            .navigationTitle("Add Variable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func addPreset(_ preset: (name: String, type: VariableType, categories: String)) {
        let v = TrackedVariableEntity(context: viewContext)
        v.id = UUID()
        v.name = preset.name
        v.type = preset.type.rawValue
        v.isDefault = false
        v.sortOrder = Int16(spot.sortedVariables.count)
        v.spot = spot
        if !preset.categories.isEmpty {
            v.categoryOptions = preset.categories.components(separatedBy: ",") as NSArray
        }
        try? viewContext.save()
    }

    private func addCustom() {
        let v = TrackedVariableEntity(context: viewContext)
        v.id = UUID()
        v.name = customName
        v.type = variableType.rawValue
        v.isDefault = false
        v.sortOrder = Int16(spot.sortedVariables.count)
        v.spot = spot
        if variableType == .category && !categoryOptions.isEmpty {
            v.categoryOptions = categoryOptions.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } as NSArray
        }
        try? viewContext.save()
    }
}
