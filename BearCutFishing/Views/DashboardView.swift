import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var vm: FishingViewModel

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        if vm.isLoading {
                            ProgressView("Loading conditions...")
                                .padding(.top, 40)
                        }

                        if let err = vm.errorMessage {
                            ErrorBannerView(message: err)
                        }

                        // Prediction cards per tracked variable
                        if let spot = vm.activeSpot {
                            ForEach(spot.sortedVariables, id: \.id) { variable in
                                if let pred = vm.predictions[variable.id ?? UUID()] {
                                    VariablePredictionCard(
                                        variableName: variable.name ?? "Unknown",
                                        prediction: pred
                                    )
                                }
                            }
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

                        // Log trip button
                        LogNightButtonView()

                        // Footer
                        if let updated = vm.lastUpdated {
                            Text("Updated \(updated, style: .relative) ago  •  \(vm.activeSpot?.name ?? "")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 20)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(vm.activeSpot?.name ?? "BiteLogic")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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

// MARK: - Variable Prediction Card

struct VariablePredictionCard: View {
    let variableName: String
    let prediction: VariablePrediction

    var level: ActivityLevel {
        ActivityLevel.from(rating: prediction.predictedRating)
    }

    var body: some View {
        VStack(spacing: 0) {
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
                VStack(alignment: .trailing) {
                    // Show rating as stars
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: Double(star) <= prediction.predictedRating.rounded() ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                    Text(String(format: "%.1f / 5", prediction.predictedRating))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(prediction.engineType)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding()
            .background(level.color)

            // Feature importance breakdown
            if !prediction.featureImportances.isEmpty {
                VStack(spacing: 6) {
                    ForEach(prediction.featureImportances.prefix(6), id: \.name) { feature in
                        HStack(spacing: 8) {
                            Text(feature.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray4))
                                .frame(width: 60, height: 8)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.accentColor)
                                        .frame(width: max(4, CGFloat(feature.importance) * 60))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 4))
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
