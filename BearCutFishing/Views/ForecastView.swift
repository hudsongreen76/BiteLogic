import SwiftUI

// MARK: - Forecast Tab

struct ForecastView: View {
    @EnvironmentObject var vm: FishingViewModel
    @StateObject private var forecastVM = ForecastViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        if forecastVM.isLoading {
                            ProgressView("Loading 3-day forecast...")
                                .padding(.top, 40)
                        }

                        if forecastVM.errorMessage != nil {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Using demo data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }

                        if !forecastVM.allBlocks.isEmpty {
                            // Activity chart
                            ForecastChartCard(forecastVM: forecastVM)

                            // Day-grouped sections
                            ForEach(forecastVM.forecastDays) { day in
                                ForecastDaySection(
                                    day: day,
                                    forecastVM: forecastVM
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("3-Day Forecast")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await forecastVM.loadForecast() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                if let spot = vm.activeSpot {
                    forecastVM.spotLat = spot.latitude
                    forecastVM.spotLon = spot.longitude
                    forecastVM.spotStationId = spot.noaaStationId ?? "8723214"
                    forecastVM.spotTimezone = spot.timezone ?? "America/New_York"
                    forecastVM.spotId = spot.id ?? UUID()
                    forecastVM.trackedVariableIds = spot.sortedVariables.compactMap { $0.id }
                }
                await forecastVM.loadForecast()
            }
        }
    }
}

// MARK: - Forecast Chart Card

struct ForecastChartCard: View {
    @ObservedObject var forecastVM: ForecastViewModel

    var body: some View {
        CardView(title: "Activity Forecast", systemImage: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: 8) {
                if let block = forecastVM.selectedBlock {
                    HStack(spacing: 6) {
                        Text(block.dayLabel)
                            .font(.caption.bold())
                        Text(block.timeRangeLabel)
                            .font(.caption.bold())
                        if let firstPred = block.predictions.values.first {
                            Text(String(format: "%.1f / 5", firstPred.predictedRating))
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                        }
                    }
                } else {
                    Text("Drag to explore forecast")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                ForecastChartShape(
                    blocks: forecastVM.allBlocks,
                    selectedIndex: $forecastVM.selectedBlockIndex
                )
                .frame(height: 180)
            }
        }
    }
}

// MARK: - Forecast Chart Shape

struct ForecastChartShape: View {
    let blocks: [ForecastBlock]
    @Binding var selectedIndex: Int?

    private let topInset: CGFloat = 20
    private let bottomInset: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let points = chartPoints(width: w, height: h)

            ZStack {
                // Grid lines
                ForEach([1.0, 2.0, 3.0, 4.0, 5.0], id: \.self) { rating in
                    let y = yForRating(rating, height: h)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color(.systemGray5), lineWidth: 0.5)
                }

                // Day separators
                ForEach(daySeparatorIndices(), id: \.self) { idx in
                    let x = xForIndex(idx, width: w)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: topInset))
                        path.addLine(to: CGPoint(x: x, y: h - bottomInset))
                    }
                    .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    Text(blocks[idx].dayLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .position(x: x + 14, y: h - 8)
                }

                // Line and fill
                if !points.isEmpty {
                    Path { path in
                        path.move(to: CGPoint(x: points.first!.x, y: h - bottomInset))
                        for pt in points { path.addLine(to: pt) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: h - bottomInset))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color.green.opacity(0.25), Color.green.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    ))

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for pt in points.dropFirst() { path.addLine(to: pt) }
                    }
                    .stroke(Color.green, lineWidth: 2)

                    ForEach(Array(points.enumerated()), id: \.offset) { idx, pt in
                        let rating = primaryRating(for: blocks[idx])
                        Circle()
                            .fill(ActivityLevel.from(rating: rating).color)
                            .frame(width: selectedIndex == idx ? 10 : 5,
                                   height: selectedIndex == idx ? 10 : 5)
                            .position(pt)
                    }
                }

                // NOW line
                if let nowIdx = nowBlockIndex() {
                    let x = xForIndex(nowIdx, width: w)
                    Rectangle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 1.5, height: h - topInset - bottomInset)
                        .position(x: x, y: (topInset + h - bottomInset) / 2)
                    Text("NOW")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.red)
                        .position(x: x, y: topInset - 8)
                }

                // Scrub line
                if let idx = selectedIndex, points.indices.contains(idx) {
                    Rectangle()
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 1.5, height: h - topInset - bottomInset)
                        .position(x: points[idx].x, y: (topInset + h - bottomInset) / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let fraction = val.location.x / w
                        let idx = Int((fraction * CGFloat(blocks.count - 1)).rounded())
                        selectedIndex = min(max(idx, 0), blocks.count - 1)
                    }
                    .onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            selectedIndex = nil
                        }
                    }
            )
        }
    }

    private func primaryRating(for block: ForecastBlock) -> Double {
        block.predictions.values.first?.predictedRating ?? 3.0
    }

    private func chartPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        blocks.enumerated().map { idx, block in
            CGPoint(
                x: xForIndex(idx, width: width),
                y: yForRating(primaryRating(for: block), height: height)
            )
        }
    }

    private func xForIndex(_ idx: Int, width: CGFloat) -> CGFloat {
        CGFloat(idx) / CGFloat(max(blocks.count - 1, 1)) * width
    }

    private func yForRating(_ rating: Double, height: CGFloat) -> CGFloat {
        let plotHeight = height - topInset - bottomInset
        return topInset + plotHeight - CGFloat((rating - 1) / 4.0) * plotHeight
    }

    private func daySeparatorIndices() -> [Int] {
        var result: [Int] = []
        let calendar = Calendar.current
        for i in 1..<blocks.count {
            if !calendar.isDate(blocks[i].startTime, inSameDayAs: blocks[i - 1].startTime) {
                result.append(i)
            }
        }
        return result
    }

    private func nowBlockIndex() -> Int? {
        let now = Date()
        return blocks.firstIndex { $0.startTime <= now && $0.endTime > now }
    }
}

// MARK: - Forecast Block Row

struct ForecastBlockRow: View {
    let block: ForecastBlock
    let isHighlighted: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                let rating = block.predictions.values.first?.predictedRating ?? 3.0
                let level = ActivityLevel.from(rating: rating)

                RoundedRectangle(cornerRadius: 4)
                    .fill(level.color)
                    .frame(width: 4, height: 40)

                Image(systemName: level.icon)
                    .font(.caption)
                    .foregroundColor(level.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.timeRangeLabel)
                        .font(.subheadline.bold())
                    HStack(spacing: 4) {
                        Text(level.rawValue)
                            .font(.caption2)
                            .foregroundColor(level.color)
                        Text(block.conditions.tideStage.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text(String(format: "%.1f", rating))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(level.color)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            }

            if isExpanded {
                VStack(spacing: 8) {
                    Divider()
                    HStack(spacing: 12) {
                        MiniLabel(icon: "wind",
                                  value: String(format: "%.0f mph", block.conditions.windMph))
                        MiniLabel(icon: "water.waves",
                                  value: String(format: "%.1f ft", block.conditions.tideHeight))
                        MiniLabel(icon: "thermometer",
                                  value: String(format: "%.0fF", block.conditions.waterTempF))
                        MiniLabel(icon: "barometer",
                                  value: String(format: "%+.1f", block.conditions.pressureChangeRate))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHighlighted
                      ? Color.orange.opacity(0.1)
                      : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHighlighted ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }
}

// MARK: - Mini Condition Label

struct MiniLabel: View {
    let icon: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Day Section

struct ForecastDaySection: View {
    let day: ForecastDay
    @ObservedObject var forecastVM: ForecastViewModel
    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.caption)
                        .foregroundColor(.accentColor)

                    Text(day.dayLabel)
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(day.blocks.count) blocks")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(day.blocks) { block in
                        let blockIndex = forecastVM.allBlocks.firstIndex(
                            where: { $0.id == block.id }
                        )
                        ForecastBlockRow(
                            block: block,
                            isHighlighted: forecastVM.selectedBlockIndex == blockIndex
                        )
                        .id(block.id)
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}
