import SwiftUI

// MARK: - Spot Comparison View
//
// Shows all saved spots side-by-side with their current bite predictions.
// Uses cached conditions when available, otherwise falls back to
// time-of-day / moon-phase heuristics (location-independent factors).

struct SpotComparisonView: View {
    @EnvironmentObject var vm: FishingViewModel
    @ObservedObject var spotManager: SpotManager

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if spotManager.spots.isEmpty {
                            emptyState
                        } else {
                            headerNote
                            ForEach(spotManager.spots, id: \.id) { spot in
                                SpotComparisonCard(
                                    spot: spot,
                                    isActive: spot.id == spotManager.activeSpot?.id
                                ) {
                                    spotManager.setActiveSpot(spot)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Compare Spots")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No spots saved yet.")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Add spots from the Dashboard to compare them here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private var headerNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Predictions based on last cached conditions per spot.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Spot Comparison Card

struct SpotComparisonCard: View {
    let spot: FishingSpotEntity
    let isActive: Bool
    let onSelect: () -> Void

    private var spotId: UUID { spot.id ?? UUID() }

    /// Conditions for this spot: cached if available, else current-time defaults.
    private var conditions: EnvironmentalConditions {
        if let cache = ConditionsCache.shared.load(spotId: spotId) {
            var c = cache.conditions.toConditions
            // Update time of day to NOW (cached weather may be hours old)
            let cal = Calendar.current
            let hour = cal.component(.hour, from: Date())
            let minute = cal.component(.minute, from: Date())
            c.timeOfDay = Double(hour) + Double(minute) / 60.0
            c.isDaylight = hour >= 6 && hour < 20
            let moon = MoonPhaseData.calculate(for: Date())
            c.moonPhase = moon.phase
            c.moonIllumination = moon.illumination
            return c
        }
        // No cache — use minimal defaults with current time/moon
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        let minute = cal.component(.minute, from: Date())
        let moon = MoonPhaseData.calculate(for: Date())
        return EnvironmentalConditions(
            windMph: 0,
            windDirection: 0,
            tideHeight: 0,
            tideChangeRate: 0,
            tideStage: .slack,
            moonPhase: moon.phase,
            moonIllumination: moon.illumination,
            waterTempF: 75,
            airTempF: 78,
            pressureHpa: 1013,
            pressureChangeRate: 0,
            precipitationMm: 0,
            waveHeightM: 0,
            wavePeriodS: 0,
            cloudCoverPct: 50,
            windGustsMph: 0,
            timeOfDay: Double(hour) + Double(minute) / 60.0,
            isDaylight: hour >= 6 && hour < 20,
            isEstimatedWind: true,
            isEstimatedWaterTemp: true,
            isEstimatedPressure: true,
            isEstimatedTide: true
        )
    }

    /// Prediction for the first (primary) variable at this spot.
    private var primaryPrediction: VariablePrediction? {
        guard let variable = spot.sortedVariables.first,
              let varId = variable.id else { return nil }
        return PredictionManager.shared.predict(
            conditions: conditions,
            spotId: spotId,
            variableId: varId
        )
    }

    private var cacheAge: String? {
        ConditionsCache.shared.load(spotId: spotId)?.ageDescription
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(spot.name ?? "Unknown Spot")
                                .font(.headline)
                                .foregroundColor(.primary)
                            if isActive {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                        if let age = cacheAge {
                            Text("Data: \(age)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No cached data — rough estimate")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    Spacer()
                    if let pred = primaryPrediction {
                        let level = ActivityLevel.from(rating: pred.predictedRating)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.0f%%", pred.percentage))
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundColor(level.color)
                            HStack(spacing: 3) {
                                Image(systemName: level.icon)
                                    .font(.caption)
                                Text(level.rawValue)
                                    .font(.caption.bold())
                            }
                            .foregroundColor(level.color)
                        }
                    }
                }
                .padding()
                .background(isActive ? Color.accentColor.opacity(0.06) : Color(.secondarySystemBackground))

                // Per-variable mini row
                let variables = spot.sortedVariables
                if variables.count > 1 {
                    Divider()
                    HStack(spacing: 0) {
                        ForEach(variables.prefix(4), id: \.id) { variable in
                            if let varId = variable.id {
                                let pred = PredictionManager.shared.predict(
                                    conditions: conditions,
                                    spotId: spotId,
                                    variableId: varId
                                )
                                let level = ActivityLevel.from(rating: pred.predictedRating)
                                VStack(spacing: 3) {
                                    Text(variable.name ?? "")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Text(String(format: "%.0f%%", pred.percentage))
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(level.color)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color(.secondarySystemBackground))
                                if variable.id != variables.prefix(4).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}
