import SwiftUI

struct TideGraphCard: View {
    @EnvironmentObject var vm: FishingViewModel
    @State private var isExpanded = false

    var body: some View {
        CardView(title: "Tide - \(vm.activeSpot?.name ?? "---")", systemImage: "water.waves") {
            VStack(alignment: .leading, spacing: 8) {
                if vm.tideReadings.isEmpty && !vm.isLoading {
                    Text("No tide data available for this spot")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else if let reading = vm.tideReadingForScrub() {
                    HStack {
                        Text(reading.time, style: .time)
                            .font(.caption.bold())
                        Text(String(format: "%.2f ft", reading.heightFt))
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(String(format: "%.2f ft", vm.currentTideHeight))
                            .font(.caption.bold())
                        Text(vm.currentTideStage.label)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f ft/hr", vm.tideChangeRate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                TideGraphShape(readings: vm.tideReadings,
                               extrema: vm.tideExtrema,
                               scrubbingIndex: $vm.scrubbingIndex)
                    .frame(height: 160)

                if !vm.tideExtrema.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(vm.tideExtrema) { ex in
                                TideExtremaChip(extrema: ex)
                            }
                        }
                    }
                }

                if isExpanded {
                    Divider()
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Direction")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(vm.currentTideStage.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Change Rate")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f ft/hr", vm.tideChangeRate))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(vm.tideChangeRate > 0.15 ? .green : .orange)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Height")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f ft", vm.currentTideHeight))
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    }

                    if !vm.tideExtrema.isEmpty {
                        let upcoming = vm.tideExtrema.filter { $0.time > Date() }.prefix(2)
                        if !upcoming.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("UPCOMING")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                ForEach(Array(upcoming)) { ex in
                                    HStack {
                                        Text(ex.isHigh ? "High" : "Low")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(ex.isHigh ? .blue : .cyan)
                                        Spacer()
                                        Text(String(format: "%.1f ft", ex.heightFt))
                                            .font(.caption)
                                        Text("at")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(ex.time, style: .time)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            }
        }
    }
}

// MARK: - Tide Graph Shape with Scrub

struct TideGraphShape: View {
    let readings: [TideReading]
    let extrema: [TideExtrema]
    @Binding var scrubbingIndex: Int?

    private let topInset: CGFloat = 32
    private let bottomInset: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let points = chartPoints(width: w, height: h)

            ZStack {
                if !points.isEmpty {
                    Path { path in
                        path.move(to: CGPoint(x: points.first!.x, y: h))
                        for pt in points { path.addLine(to: pt) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: h))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ))

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for pt in points.dropFirst() { path.addLine(to: pt) }
                    }
                    .stroke(Color.blue, lineWidth: 2)
                }

                ForEach(extrema) { ex in
                    if let pt = pointForExtrema(ex, width: w, height: h) {
                        let labelX = min(max(pt.x, 28), w - 28)
                        let labelY = ex.isHigh
                            ? max(pt.y - 20, 14)
                            : min(pt.y + 20, h - 14)
                        VStack(spacing: 1) {
                            Text(ex.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(ex.isHigh ? .blue : .cyan)
                            Text(String(format: "%.1f'", ex.heightFt))
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(ex.time, style: .time)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .position(x: labelX, y: labelY)
                    }
                }

                if let nowX = nowX(width: w) {
                    Rectangle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: 1.5, height: h)
                        .position(x: nowX, y: h / 2)

                    Text("NOW")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.red)
                        .position(x: nowX, y: 6)
                }

                if let idx = scrubbingIndex, points.indices.contains(idx) {
                    Rectangle()
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 1.5, height: h)
                        .position(x: points[idx].x, y: h / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let fraction = val.location.x / w
                        let idx = Int((fraction * CGFloat(readings.count - 1)).rounded())
                        scrubbingIndex = min(max(idx, 0), readings.count - 1)
                    }
                    .onEnded { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            scrubbingIndex = nil
                        }
                    }
            )
        }
    }

    private func chartPoints(width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard !readings.isEmpty else { return [] }
        let plotHeight = height - topInset - bottomInset
        let minH = readings.map(\.heightFt).min() ?? 0
        let maxH = readings.map(\.heightFt).max() ?? 3
        let range = max(maxH - minH, 0.5)
        let count = readings.count
        return readings.enumerated().map { idx, reading in
            let x = CGFloat(idx) / CGFloat(max(count - 1, 1)) * width
            let normalized = (reading.heightFt - minH) / range
            let y = topInset + plotHeight - CGFloat(normalized) * plotHeight
            return CGPoint(x: x, y: y)
        }
    }

    private func pointForExtrema(_ ex: TideExtrema, width: CGFloat, height: CGFloat) -> CGPoint? {
        // Find the hourly reading whose time is closest to the hi_lo extrema time
        guard let idx = readings.enumerated().min(by: {
            abs($0.element.time.timeIntervalSince(ex.time)) < abs($1.element.time.timeIntervalSince(ex.time))
        })?.offset else { return nil }
        let pts = chartPoints(width: width, height: height)
        guard pts.indices.contains(idx) else { return nil }
        return pts[idx]
    }

    private func nowX(width: CGFloat) -> CGFloat? {
        guard !readings.isEmpty else { return nil }
        let now = Date()
        let times = readings.map { $0.time }
        guard let first = times.first, let last = times.last else { return nil }
        let total = last.timeIntervalSince(first)
        guard total > 0 else { return nil }
        let elapsed = now.timeIntervalSince(first)
        let fraction = CGFloat(elapsed / total)
        guard fraction >= 0 && fraction <= 1 else { return nil }
        return fraction * width
    }
}

// MARK: - Extrema Chip

struct TideExtremaChip: View {
    let extrema: TideExtrema

    var body: some View {
        VStack(spacing: 2) {
            Text(extrema.isHigh ? "High" : "Low")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(extrema.isHigh ? .blue : .cyan)
            Text(String(format: "%.1f ft", extrema.heightFt))
                .font(.caption2)
            Text(extrema.time, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}
