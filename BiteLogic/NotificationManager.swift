import Foundation
import Combine
import UserNotifications
import SwiftUI

// MARK: - Notification Manager

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined
    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    @Published var notificationThreshold: Double {
        didSet { UserDefaults.standard.set(notificationThreshold, forKey: "notificationThreshold") }
    }
    @Published var morningBriefingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(morningBriefingEnabled, forKey: "morningBriefingEnabled")
            if morningBriefingEnabled {
                scheduleMorningBriefing()
            } else {
                cancelMorningBriefing()
            }
        }
    }
    @Published var morningBriefingHour: Int {
        didSet {
            UserDefaults.standard.set(morningBriefingHour, forKey: "morningBriefingHour")
            if morningBriefingEnabled { scheduleMorningBriefing() }
        }
    }

    private let center = UNUserNotificationCenter.current()

    init() {
        notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        notificationThreshold = UserDefaults.standard.double(forKey: "notificationThreshold").nonZeroOr(3.5)
        morningBriefingEnabled = UserDefaults.standard.bool(forKey: "morningBriefingEnabled")
        morningBriefingHour = {
            let h = UserDefaults.standard.integer(forKey: "morningBriefingHour")
            return h == 0 ? 6 : h
        }()
    }

    // MARK: - Permission

    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await center.notificationSettings()
            permissionStatus = settings.authorizationStatus
            if granted && morningBriefingEnabled {
                scheduleMorningBriefing()
            }
        } catch {
            print("Notification permission error: \(error)")
        }
    }

    func refreshPermissionStatus() async {
        let settings = await center.notificationSettings()
        permissionStatus = settings.authorizationStatus
    }

    var isAuthorized: Bool {
        permissionStatus == .authorized || permissionStatus == .provisional
    }

    // MARK: - Condition Alert

    /// Call after a successful data refresh to potentially alert the user.
    func checkConditionsAndNotify(
        predictions: [UUID: VariablePrediction],
        variables: [TrackedVariableEntity],
        spotName: String
    ) {
        guard notificationsEnabled, isAuthorized else { return }

        // Find variables that exceed the threshold
        let hotVariables = variables.compactMap { variable -> (name: String, rating: Double)? in
            guard let id = variable.id,
                  let pred = predictions[id],
                  pred.predictedRating >= notificationThreshold else { return nil }
            return (name: variable.name ?? "Activity", rating: pred.predictedRating)
        }

        guard !hotVariables.isEmpty else { return }

        let variableList = hotVariables.map { "\($0.name) (\(String(format: "%.1f", $0.rating))★)" }
            .joined(separator: ", ")

        let level = ActivityLevel.from(rating: hotVariables.map(\.rating).max() ?? notificationThreshold)

        let content = UNMutableNotificationContent()
        content.title = "\(level.rawValue) conditions at \(spotName)!"
        content.body = "Right now: \(variableList)"
        content.sound = .default

        // Deliver immediately (in-app alert style)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "conditions_\(spotName)_\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    // MARK: - Morning Briefing

    func scheduleMorningBriefing() {
        cancelMorningBriefing()
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Good morning, angler!"
        content.body = "Open BiteLogic to check today's bite forecast."
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = morningBriefingHour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "morning_briefing",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    func cancelMorningBriefing() {
        center.removePendingNotificationRequests(withIdentifiers: ["morning_briefing"])
    }

    // MARK: - Settings View

    @ViewBuilder
    func settingsView() -> some View {
        NotificationSettingsView()
    }
}

private extension Double {
    func nonZeroOr(_ fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
    @ObservedObject private var manager = NotificationManager.shared
    @State private var showPermissionAlert = false

    var body: some View {
        CardView(title: "Notifications", systemImage: "bell.badge") {
            VStack(alignment: .leading, spacing: 12) {
                if manager.permissionStatus == .denied {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Notifications are blocked. Enable them in Settings → BiteLogic.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Master toggle
                    Toggle(isOn: $manager.notificationsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Condition Alerts")
                                .font(.subheadline.weight(.medium))
                            Text("Alert when predicted bite rating is high")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: manager.notificationsEnabled) { _, enabled in
                        if enabled && !manager.isAuthorized {
                            Task { await manager.requestPermission() }
                        }
                    }

                    if manager.notificationsEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Alert threshold")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1f★", manager.notificationThreshold))
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                            }
                            Slider(value: $manager.notificationThreshold, in: 2.5...5.0, step: 0.5)
                                .tint(.accentColor)
                        }
                    }

                    Divider()

                    // Morning briefing
                    Toggle(isOn: $manager.morningBriefingEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Morning Briefing")
                                .font(.subheadline.weight(.medium))
                            Text("Daily reminder to check conditions")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if manager.morningBriefingEnabled {
                        HStack {
                            Text("Briefing time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("Hour", selection: $manager.morningBriefingHour) {
                                ForEach([4, 5, 6, 7, 8, 9], id: \.self) { h in
                                    Text(hourLabel(h)).tag(h)
                                }
                            }
                            .pickerStyle(.menu)
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .task { await manager.refreshPermissionStatus() }
    }

    private func hourLabel(_ hour: Int) -> String {
        let h = hour > 12 ? hour - 12 : hour
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(h):00 \(suffix)"
    }
}
