import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var vm: FishingViewModel
    @ObservedObject var spotManager: SpotManager
    @ObservedObject var predictionManager = PredictionManager.shared

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        // Prediction mode toggle
                        PredictionModeToggle()

                        if vm.isLoading {
                            LoadingBarView(
                                progress: vm.loadingProgress,
                                step: vm.loadingStep
                            )
                            .padding(.top, 40)
                        }

                        if let err = vm.errorMessage {
                            ErrorBannerView(message: err)
                        }

                        if vm.isShowingCachedData {
                            CachedDataBannerView(age: vm.cachedDataAge)
                        }

                        // Prediction cards per tracked variable — tap to open variable forecast
                        if let spot = vm.activeSpot {
                            ForEach(spot.sortedVariables, id: \.id) { variable in
                                if let varId = variable.id,
                                   let pred = vm.predictions[varId] {
                                    NavigationLink {
                                        ForecastView(filterVariable: (id: varId, name: variable.name ?? "Unknown"))
                                    } label: {
                                        VariablePredictionCard(
                                            variableName: variable.name ?? "Unknown",
                                            prediction: pred
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Solunar periods
                        if let spot = vm.activeSpot {
                            SolunarCardView(timezone: spot.timezone ?? "America/New_York")
                        }

                        // Tide Graph
                        TideGraphCard()

                        // Wind
                        WindCardView()

                        // Moon
                        MoonCardView()

                        // Water Temp
                        WaterTempCardView()

                        // Pressure
                        PressureCardView()

                        // Notification settings
                        NotificationManager.shared.settingsView()

                        // Log trip button
                        LogNightButtonView()

                        // Footer
                        if let updated = vm.lastUpdated {
                            Text("Updated \(updated, style: .relative) ago")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 20)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SpotSwitcherView(spotManager: spotManager)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if let spot = vm.activeSpot {
                            NavigationLink {
                                VariableManagerView(spot: spot)
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                        }
                        Button {
                            Task { await vm.loadAll() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Variable Prediction Card

struct VariablePredictionCard: View {
    let variableName: String
    let prediction: VariablePrediction

    var level: ActivityLevel {
        ActivityLevel.from(rating: prediction.predictedRating)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with activity level and percentage
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(variableName.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                    HStack(spacing: 6) {
                        Image(systemName: level.icon)
                            .font(.title2)
                        Text(level.rawValue)
                            .font(.system(size: 24, weight: .black))
                    }
                    .foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f%%", prediction.percentage))
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: Double(star) <= prediction.predictedRating.rounded() ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    Text(prediction.engineType)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    // Confidence interval range bar
                    let lowFrac = CGFloat((prediction.confidenceInterval.low - 1.0) / 4.0)
                    let highFrac = CGFloat((prediction.confidenceInterval.high - 1.0) / 4.0)
                    let centerFrac = CGFloat(prediction.percentage / 100.0)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.2))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.45))
                                .frame(width: max(4, (highFrac - lowFrac) * geo.size.width))
                                .offset(x: lowFrac * geo.size.width)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.white)
                                .frame(width: 3)
                                .offset(x: max(0, min(geo.size.width - 3, centerFrac * geo.size.width - 1.5)))
                        }
                    }
                    .frame(height: 4)
                    Text(String(format: "±%.0f–%.0f%%",
                                prediction.confidenceInterval.low / 5.0 * 100,
                                prediction.confidenceInterval.high / 5.0 * 100))
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding()
            .background(level.color)

            // Per-factor breakdown with colored bars
            if !prediction.factors.isEmpty {
                VStack(spacing: 8) {
                    ForEach(prediction.factors, id: \.name) { factor in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(factor.name)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .frame(width: 100, alignment: .leading)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color(.systemGray5))
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(factor.color)
                                            .frame(width: max(4, geo.size.width * CGFloat(factor.score)))
                                    }
                                }
                                .frame(height: 10)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "%.0f%%", factor.score * 100))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(factor.color)
                                    if !factor.displayValue.isEmpty {
                                        Text(factor.displayValue)
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 50, alignment: .trailing)
                            }
                            Text(factor.note)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.leading, 100)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
            }
        }
        .cornerRadius(16)
        .shadow(color: level.color.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Error Banner
struct ErrorBannerView: View {
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Using estimated data")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            Text(message)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Cached Data Banner

struct CachedDataBannerView: View {
    let age: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.caption)
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline — showing cached data")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                Text("Last updated \(age)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.blue.opacity(0.08))
        .cornerRadius(10)
    }
}

// MARK: - Prediction Mode Toggle

struct PredictionModeToggle: View {
    @ObservedObject var manager = PredictionManager.shared
    @EnvironmentObject var vm: FishingViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                modeButton(.heuristic)
                modeButton(.learned)
            }
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(12)

            Text(manager.predictionMode.description)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func modeButton(_ mode: PredictionMode) -> some View {
        let isSelected = manager.predictionMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                manager.predictionMode = mode
                vm.computePredictions()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.caption)
                Text(mode.label)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : .secondary)
            .cornerRadius(10)
        }
    }
}

// MARK: - Loading Bar

struct LoadingBarView: View {
    let progress: Double
    let step: String

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .animation(.easeInOut(duration: 0.3), value: progress)
            if !step.isEmpty {
                Text(step)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Card Container
struct CardView<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            content
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}
