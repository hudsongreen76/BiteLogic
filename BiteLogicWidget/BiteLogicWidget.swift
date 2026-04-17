import WidgetKit
import SwiftUI

// MARK: - Widget Timeline Provider

struct BiteLogicProvider: TimelineProvider {

    func placeholder(in context: Context) -> BiteLogicEntry {
        BiteLogicEntry(date: Date(), spotName: "Bear Cut", percentage: 72, activityLevel: .active, cacheAge: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BiteLogicEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BiteLogicEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every hour
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }

    private func loadEntry() -> BiteLogicEntry {
        // Read from shared UserDefaults (App Group)
        let defaults = UserDefaults(suiteName: "group.com.bitelogic.app") ?? .standard

        let spotName = defaults.string(forKey: "widget_spotName") ?? "No Spot"
        let percentage = defaults.double(forKey: "widget_percentage")
        let activityRaw = defaults.string(forKey: "widget_activityLevel") ?? ActivityLevel.moderate.rawValue
        let activity = ActivityLevel(rawValue: activityRaw) ?? .moderate
        let cacheAge = defaults.string(forKey: "widget_cacheAge")

        return BiteLogicEntry(
            date: Date(),
            spotName: spotName,
            percentage: percentage == 0 ? 50 : percentage,
            activityLevel: activity,
            cacheAge: cacheAge
        )
    }
}

// MARK: - Timeline Entry

struct BiteLogicEntry: TimelineEntry {
    let date: Date
    let spotName: String
    let percentage: Double
    let activityLevel: ActivityLevel
    let cacheAge: String?
}

// MARK: - Widget Views

struct BiteLogicWidgetEntryView: View {
    var entry: BiteLogicEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var smallView: some View {
        ZStack {
            entry.activityLevel.color.opacity(0.15)
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: entry.activityLevel.icon)
                        .font(.caption)
                        .foregroundColor(entry.activityLevel.color)
                    Text(entry.spotName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                }
                Text(String(format: "%.0f%%", entry.percentage))
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(entry.activityLevel.color)
                Text(entry.activityLevel.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(entry.activityLevel.color)
                if let age = entry.cacheAge {
                    Text(age)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
        }
    }

    private var mediumView: some View {
        ZStack {
            entry.activityLevel.color.opacity(0.10)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(entry.spotName, systemImage: "mappin.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(String(format: "%.0f%%", entry.percentage))
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundColor(entry.activityLevel.color)
                    HStack(spacing: 4) {
                        Image(systemName: entry.activityLevel.icon)
                        Text(entry.activityLevel.rawValue)
                            .fontWeight(.bold)
                    }
                    .font(.subheadline)
                    .foregroundColor(entry.activityLevel.color)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("BITE SCORE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Image(systemName: "fish.fill")
                        .font(.system(size: 32))
                        .foregroundColor(entry.activityLevel.color.opacity(0.6))
                    if let age = entry.cacheAge {
                        Text("Updated \(age)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Widget Configuration

struct BiteLogicWidget: Widget {
    let kind: String = "BiteLogicWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BiteLogicProvider()) { entry in
            BiteLogicWidgetEntryView(entry: entry)
                .containerBackground(Color(.systemBackground), for: .widget)
        }
        .configurationDisplayName("Bite Score")
        .description("Shows the current bite prediction for your active fishing spot.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct BiteLogicWidgetBundle: WidgetBundle {
    var body: some Widget {
        BiteLogicWidget()
    }
}
