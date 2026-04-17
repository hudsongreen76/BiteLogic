import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct LogListView: View {
    @EnvironmentObject var vm: FishingViewModel
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingLogForm = false
    @State private var refreshID = UUID()
    @State private var csvItem: CSVShareItem?

    var filteredEntries: [LogEntryEntity] {
        // refreshID dependency forces SwiftUI to re-evaluate after save
        let _ = refreshID
        guard let spot = vm.activeSpot else { return [] }
        return spot.sortedLogEntries
    }

    var body: some View {
        NavigationView {
            Group {
                if filteredEntries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No logs yet")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Log your first trip from the Dashboard!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(filteredEntries, id: \.id) { entry in
                            LogEntryRowView(entry: entry)
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }
            }
            .navigationTitle("Fishing Log")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !filteredEntries.isEmpty {
                        Button {
                            csvItem = CSVShareItem(csvString: generateCSV())
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button { showingLogForm = true } label: {
                            Image(systemName: "plus")
                        }
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showingLogForm, onDismiss: {
                refreshID = UUID()
            }) {
                LogEntryFormView()
            }
            .sheet(item: $csvItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        let entries = filteredEntries
        for idx in offsets {
            viewContext.delete(entries[idx])
        }
        try? viewContext.save()
    }

    private func generateCSV() -> String {
        guard let spot = vm.activeSpot else { return "" }
        let entries = spot.sortedLogEntries
        let variables = spot.sortedVariables

        let dateF = DateFormatter()
        dateF.dateFormat = "yyyy-MM-dd"
        let timeF = DateFormatter()
        timeF.dateFormat = "HH:mm"

        var headers = ["Date", "Start", "End", "Wind (mph)", "Water Temp (F)", "Tide Stage", "Pressure (hPa)", "Moon Phase", "Notes"]
        headers += variables.compactMap { $0.name }
        var lines = [headers.joined(separator: ",")]

        for entry in entries {
            var row: [String] = []
            row.append(entry.date.map { dateF.string(from: $0) } ?? "")
            row.append(entry.startTime.map { timeF.string(from: $0) } ?? "")
            row.append(entry.endTime.map { timeF.string(from: $0) } ?? "")

            if let snap = entry.environmentalSnapshot {
                row.append(String(format: "%.1f", snap.windMph))
                row.append(String(format: "%.1f", snap.waterTempF))
                row.append(snap.tideStage ?? "")
                row.append(String(format: "%.0f", snap.pressureHpa))
                let moon = MoonPhaseData.calculate(for: entry.date ?? Date())
                row.append(moon.phaseName)
            } else {
                row += ["", "", "", "", ""]
            }

            let notesEscaped = (entry.notes ?? "")
                .replacingOccurrences(of: "\"", with: "\"\"")
            row.append("\"\(notesEscaped)\"")

            for variable in variables {
                if let varId = variable.id,
                   let ratings = entry.ratings as? Set<VariableRatingEntity>,
                   let rating = ratings.first(where: { $0.variable?.id == varId }) {
                    if let catValue = rating.categoryValue, !catValue.isEmpty {
                        row.append(catValue)
                    } else {
                        row.append(String(format: "%.0f", rating.ratingValue))
                    }
                } else {
                    row.append("")
                }
            }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - CSV Share Helpers

struct CSVShareItem: Identifiable {
    let id = UUID()
    let csvString: String

    var url: URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("BiteLogic_Export_\(id.uuidString).csv")
        try? csvString.write(to: tmp, atomically: true, encoding: .utf8)
        return tmp
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Log Entry Row

struct LogEntryRowView: View {
    let entry: LogEntryEntity

    private var timeRange: String {
        guard let start = entry.startTime, let end = entry.endTime else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h a"
        return "\(f.string(from: start)) - \(f.string(from: end))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date ?? Date(), style: .date)
                        .font(.subheadline.bold())
                    if !timeRange.isEmpty {
                        Text(timeRange)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                // Photo thumbnail
                if let photoData = entry.photoData, let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipped()
                        .cornerRadius(6)
                }
                // Show ratings as badges
                if let ratings = entry.ratings as? Set<VariableRatingEntity> {
                    HStack(spacing: 4) {
                        ForEach(Array(ratings).sorted(by: { ($0.variable?.sortOrder ?? 0) < ($1.variable?.sortOrder ?? 0) }).prefix(3), id: \.id) { rating in
                            if let catValue = rating.categoryValue, !catValue.isEmpty {
                                Text(catValue)
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .cornerRadius(4)
                            } else {
                                HStack(spacing: 1) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.yellow)
                                    Text(String(format: "%.0f", rating.ratingValue))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                if let snapshot = entry.environmentalSnapshot {
                    Label(String(format: "%.0f mph", snapshot.windMph),
                          systemImage: "wind")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label(String(format: "%.0fF", snapshot.waterTempF),
                          systemImage: "thermometer")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label(snapshot.tideStage ?? "---",
                          systemImage: "water.waves")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let notes = entry.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
