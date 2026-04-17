import SwiftUI
import CoreData
import Combine
import PhotosUI

// MARK: - Log Night Button (on Dashboard)

struct LogNightButtonView: View {
    @State private var showingLogSheet = false

    var body: some View {
        Button {
            showingLogSheet = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Log a Trip")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(14)
        }
        .sheet(isPresented: $showingLogSheet) {
            LogEntryFormView()
        }
    }
}

// MARK: - Log Entry Form

struct LogEntryFormView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var vm: FishingViewModel
    @Environment(\.managedObjectContext) private var viewContext

    // Date & time
    @State private var selectedDateIndex = 0
    @State private var startHour = 18  // 6 PM default
    @State private var endHour = 22    // 10 PM default

    // Ratings
    @State private var starRatings: [UUID: Double] = [:]
    @State private var categorySelections: [UUID: String] = [:]
    @State private var notes = ""

    // Photo
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?

    // Environmental data
    @State private var fetchedConditions: EnvironmentalConditions?
    @State private var fetchFailures: [FetchFailure] = []
    @State private var isFetching = false
    @State private var fetchProgress: Double = 0
    @State private var fetchStep: String = ""
    @State private var showingFailureAlert = false

    // Post-trip summary
    @State private var showingTripSummary = false
    @State private var tripSummaryItems: [(variableName: String, predicted: Double, actual: Double)] = []

    private var dateOptions: [(label: String, date: Date)] {
        let calendar = Calendar.current
        return (0...16).map { daysBack in
            let date = calendar.date(byAdding: .day, value: -daysBack, to: calendar.startOfDay(for: Date()))!
            let label: String
            if daysBack == 0 {
                label = "Today"
            } else if daysBack == 1 {
                label = "Yesterday"
            } else {
                let f = DateFormatter()
                f.dateFormat = "EEE, MMM d"
                label = f.string(from: date)
            }
            return (label, date)
        }
    }

    var body: some View {
        NavigationView {
            Form {
                // Date selection
                Section("When did you fish?") {
                    Picker("Date", selection: $selectedDateIndex) {
                        ForEach(0..<dateOptions.count, id: \.self) { idx in
                            Text(dateOptions[idx].label).tag(idx)
                        }
                    }
                    .onChange(of: selectedDateIndex) { _, _ in
                        fetchEnvironmentalData()
                    }

                    HStack {
                        Text("Start")
                        Spacer()
                        Picker("", selection: $startHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    HStack {
                        Text("End")
                        Spacer()
                        Picker("", selection: $endHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .onChange(of: startHour) { _, _ in fetchEnvironmentalData() }
                    .onChange(of: endHour) { _, _ in fetchEnvironmentalData() }
                }

                // Conditions status
                Section("Conditions") {
                    if isFetching {
                        VStack(spacing: 6) {
                            ProgressView(value: fetchProgress)
                                .progressViewStyle(.linear)
                                .tint(.accentColor)
                                .animation(.easeInOut(duration: 0.3), value: fetchProgress)
                            Text(fetchStep.isEmpty ? "Fetching conditions…" : fetchStep)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else if let conditions = fetchedConditions {
                        conditionsSummary(conditions)
                    }

                    if !fetchFailures.isEmpty {
                        Button {
                            showingFailureAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("\(fetchFailures.count) data source(s) unavailable")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Ratings
                if let spot = vm.activeSpot {
                    Section("Rate your trip") {
                        ForEach(spot.sortedVariables, id: \.id) { variable in
                            variableRatingRow(variable)
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section("Photo (optional)") {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack {
                            if let data = selectedPhotoData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipped()
                                    .cornerRadius(8)
                                Text("Change photo")
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                            } else {
                                Image(systemName: "camera")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                Text("Add a photo")
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                            }
                            Spacer()
                        }
                    }
                    .onChange(of: selectedPhotoItem) { _, item in
                        Task {
                            if let data = try? await item?.loadTransferable(type: Data.self) {
                                selectedPhotoData = data
                            }
                        }
                    }
                    if selectedPhotoData != nil {
                        Button(role: .destructive) {
                            selectedPhotoData = nil
                            selectedPhotoItem = nil
                        } label: {
                            Text("Remove photo")
                        }
                    }
                }
            }
            .navigationTitle("Log Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveEntry()
                    }
                    .fontWeight(.semibold)
                    .disabled(isFetching)
                }
            }
            .onAppear { fetchEnvironmentalData() }
            .alert("Data Fetch Failures", isPresented: $showingFailureAlert) {
                Button("Use Estimated Values", role: .cancel) {}
                Button("Retry") { fetchEnvironmentalData() }
            } message: {
                Text(fetchFailures.map { "\($0.dataType): \($0.error.localizedDescription)" }.joined(separator: "\n"))
            }
            .sheet(isPresented: $showingTripSummary, onDismiss: { dismiss() }) {
                TripSummarySheet(items: tripSummaryItems)
            }
        }
    }

    // MARK: - Variable Rating Row

    @ViewBuilder
    private func variableRatingRow(_ variable: TrackedVariableEntity) -> some View {
        let varId = variable.id ?? UUID()

        if variable.type == VariableType.category.rawValue,
           let options = variable.categoryOptions as? [String], !options.isEmpty {
            HStack {
                Text(variable.name ?? "Unknown")
                Spacer()
                Picker("", selection: Binding(
                    get: { categorySelections[varId] ?? options.first ?? "" },
                    set: { categorySelections[varId] = $0 }
                )) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        } else {
            HStack {
                Text(variable.name ?? "Unknown")
                Spacer()
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: Double(star) <= (starRatings[varId] ?? 3) ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.title2)
                            .onTapGesture { starRatings[varId] = Double(star) }
                    }
                }
            }
        }
    }

    // MARK: - Conditions Summary

    @ViewBuilder
    private func conditionsSummary(_ c: EnvironmentalConditions) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            conditionItem("Wind", value: String(format: "%.0f mph", c.windMph), estimated: c.isEstimatedWind)
            conditionItem("Tide", value: "\(c.tideStage.label)", estimated: c.isEstimatedTide)
            conditionItem("Water", value: String(format: "%.0fF", c.waterTempF), estimated: c.isEstimatedWaterTemp)
            conditionItem("Pressure", value: String(format: "%.0f hPa", c.pressureHpa), estimated: c.isEstimatedPressure)
            conditionItem("Moon", value: MoonPhaseData.calculate(for: dateOptions[selectedDateIndex].date).phaseName, estimated: false)
            conditionItem("Time", value: "\(hourLabel(startHour))-\(hourLabel(endHour))", estimated: false)
        }
    }

    private func conditionItem(_ label: String, value: String, estimated: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
            if estimated {
                Text("est.")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - Fetch

    private func fetchEnvironmentalData() {
        guard let spot = vm.activeSpot else { return }
        isFetching = true
        fetchProgress = 0
        fetchStep = ""
        fetchFailures = []

        let date = dateOptions[selectedDateIndex].date
        Task {
            let result = await EnvironmentalDataFetcher.shared.fetch(
                lat: spot.latitude,
                lon: spot.longitude,
                stationId: spot.noaaStationId ?? "",
                timezone: spot.timezone ?? TimeZone.current.identifier,
                date: date,
                startHour: startHour,
                endHour: endHour,
                onProgress: { progress, step in
                    Task { @MainActor in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            fetchProgress = progress
                            fetchStep = step
                        }
                    }
                }
            )
            fetchedConditions = result.conditions
            fetchFailures = result.failures
            isFetching = false

            if !result.failures.isEmpty {
                showingFailureAlert = true
            }
        }
    }

    // MARK: - Save

    private func saveEntry() {
        guard let spot = vm.activeSpot else { return }
        let selectedDate = dateOptions[selectedDateIndex].date
        let calendar = Calendar.current
        let spotId = spot.id ?? UUID()

        // Compute prediction summary before saving (for post-trip sheet)
        let conditions = fetchedConditions ?? vm.currentConditions
        var summaryItems: [(variableName: String, predicted: Double, actual: Double)] = []
        for variable in spot.sortedVariables {
            guard variable.type != VariableType.category.rawValue else { continue }
            let varId = variable.id ?? UUID()
            let predicted = PredictionManager.shared.predict(conditions: conditions, spotId: spotId, variableId: varId)
            let actual = starRatings[varId] ?? 3.0
            summaryItems.append((
                variableName: variable.name ?? "Unknown",
                predicted: predicted.predictedRating,
                actual: actual
            ))
        }

        let entry = LogEntryEntity(context: viewContext)
        entry.id = UUID()
        entry.date = selectedDate
        entry.startTime = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: selectedDate)
        entry.endTime = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: selectedDate)
        entry.notes = notes
        entry.createdAt = Date()
        entry.spot = spot
        entry.photoData = selectedPhotoData

        // Save ratings
        for variable in spot.sortedVariables {
            let varId = variable.id ?? UUID()
            let rating = VariableRatingEntity(context: viewContext)
            rating.id = UUID()
            rating.variable = variable
            rating.logEntry = entry

            if variable.type == VariableType.category.rawValue {
                rating.categoryValue = categorySelections[varId]
                rating.ratingValue = 0
            } else {
                rating.ratingValue = starRatings[varId] ?? 3.0
            }
        }

        // Save environmental snapshot
        let snapshot = EnvironmentalSnapshotEntity(context: viewContext)
        snapshot.id = UUID()
        snapshot.populate(from: conditions)
        snapshot.logEntry = entry

        try? viewContext.save()

        // Retrain predictions with new data
        vm.computePredictions()
        vm.objectWillChange.send()

        // Show post-trip summary if there's something to compare
        if !summaryItems.isEmpty {
            tripSummaryItems = summaryItems
            showingTripSummary = true
        } else {
            dismiss()
        }
    }

    // MARK: - Helpers

    private func hourLabel(_ hour: Int) -> String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h) \(ampm)"
    }
}

// MARK: - Trip Summary Sheet

struct TripSummarySheet: View {
    @Environment(\.dismiss) var dismiss
    let items: [(variableName: String, predicted: Double, actual: Double)]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.green)
                    Text("Trip Logged!")
                        .font(.title2.bold())
                    Text("Here's how the prediction compared to what you experienced:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(spacing: 12) {
                        ForEach(items, id: \.variableName) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.variableName.uppercased())
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                                HStack(spacing: 24) {
                                    VStack(spacing: 4) {
                                        Text("Predicted")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        starsView(rating: item.predicted, color: .green)
                                        Text(String(format: "%.1f★", item.predicted))
                                            .font(.caption.bold())
                                            .foregroundColor(.green)
                                    }
                                    .frame(maxWidth: .infinity)

                                    VStack(spacing: 4) {
                                        Image(systemName: accuracyIcon(predicted: item.predicted, actual: item.actual))
                                            .font(.title2)
                                            .foregroundColor(accuracyColor(predicted: item.predicted, actual: item.actual))
                                        Text(accuracyLabel(predicted: item.predicted, actual: item.actual))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(width: 60)

                                    VStack(spacing: 4) {
                                        Text("You Rated")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        starsView(rating: item.actual, color: .orange)
                                        Text(String(format: "%.1f★", item.actual))
                                            .font(.caption.bold())
                                            .foregroundColor(.orange)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)

                    Text("Your ratings help improve future predictions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 20)
                }
                .padding(.top, 24)
            }
            .navigationTitle("How'd We Do?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func starsView(rating: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= rating.rounded() ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(color)
            }
        }
    }

    private func accuracyIcon(predicted: Double, actual: Double) -> String {
        let diff = abs(predicted - actual)
        if diff <= 0.5 { return "checkmark.circle.fill" }
        if diff <= 1.5 { return "arrow.left.arrow.right.circle" }
        return "exclamationmark.circle"
    }

    private func accuracyColor(predicted: Double, actual: Double) -> Color {
        let diff = abs(predicted - actual)
        if diff <= 0.5 { return .green }
        if diff <= 1.5 { return .orange }
        return .red
    }

    private func accuracyLabel(predicted: Double, actual: Double) -> String {
        let diff = abs(predicted - actual)
        if diff <= 0.5 { return "Spot on!" }
        if diff <= 1.5 { return "Close" }
        if predicted > actual { return "Overpredicted" }
        return "Underpredicted"
    }
}
