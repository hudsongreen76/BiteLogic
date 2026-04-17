import SwiftUI

// MARK: - Estimated Badge

struct EstimatedBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "info.circle")
                .font(.system(size: 9))
            Text("Est.")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(4)
    }
}

// MARK: - Wind Color Helper

private func windColor(for mph: Double) -> Color {
    if mph < 8 { return .green }
    if mph < 14 { return .blue }
    if mph < 18 { return .orange }
    return .red
}

private func windLevel(for mph: Double) -> String {
    if mph < 8 { return "Calm" }
    if mph < 14 { return "Light" }
    if mph < 18 { return "Moderate" }
    return "Strong"
}

// MARK: - Wind Card

struct WindCardView: View {
    @EnvironmentObject var vm: FishingViewModel

    var body: some View {
        CardView(title: "Wind", systemImage: "wind") {
            if let weather = vm.weather {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.0f", weather.windMph))
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .foregroundColor(windColor(for: weather.windMph))
                                Text("mph")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if vm.weatherIsDemo { EstimatedBadge() }
                            }
                            Text("\(weather.windDirection) - \(windLevel(for: weather.windMph))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Today")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            HStack(alignment: .bottom, spacing: 1.5) {
                                ForEach(vm.hourlyWind, id: \.hour) { item in
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(windColor(for: item.mph).opacity(0.7))
                                        .frame(width: 4, height: max(2, CGFloat(item.mph) * 1.5))
                                }
                            }
                            .frame(height: 36)
                        }
                    }

                    if !vm.dailySummaries.isEmpty {
                        Divider()
                        Text("3-DAY FORECAST")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)

                        ForEach(vm.dailySummaries) { day in
                            HStack(spacing: 10) {
                                Text(day.dayLabel)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .frame(width: 60, alignment: .leading)

                                HStack(alignment: .bottom, spacing: 1) {
                                    ForEach(day.hourlyWind, id: \.0) { item in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(windColor(for: item.1).opacity(0.7))
                                            .frame(width: 3, height: max(2, CGFloat(item.1) * 1.0))
                                    }
                                }
                                .frame(height: 24)

                                Spacer()

                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "%.0f", day.avgWindMph))
                                        .font(.caption.bold())
                                        .foregroundColor(windColor(for: day.avgWindMph))
                                    Text("avg")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }

                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "%.0f", day.maxWindMph))
                                        .font(.caption.bold())
                                        .foregroundColor(windColor(for: day.maxWindMph))
                                    Text("max")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }

                                Text(day.avgWindDir)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 28)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
    }
}

// MARK: - Moon Card

struct MoonCardView: View {
    @EnvironmentObject var vm: FishingViewModel

    var body: some View {
        CardView(title: "Moon", systemImage: "moon.stars") {
            VStack(alignment: .leading, spacing: 6) {
                Text(vm.moonPhase.emoji)
                    .font(.system(size: 38))
                Text(vm.moonPhase.phaseName)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text("\(Int(vm.moonPhase.illumination * 100))% lit")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if vm.moonPhase.isNewMoon {
                    Text("Dark skies - favorable")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
    }
}

// MARK: - Water Temp Card

struct WaterTempCardView: View {
    @EnvironmentObject var vm: FishingViewModel

    var tempColor: Color {
        guard let w = vm.weather?.waterTempF else { return .gray }
        if w < 72 { return .blue }
        if w < 78 { return .green }
        if w < 84 { return Color(red: 0.1, green: 0.75, blue: 0.4) }
        return .orange
    }

    var tempNote: String {
        guard let w = vm.weather?.waterTempF else { return "" }
        if w < 72 { return "Cool - below ideal" }
        if w < 78 { return "Good - fish comfortable" }
        if w < 84 { return "Ideal - peak activity" }
        return "Warm - above ideal"
    }

    private func colorForTemp(_ t: Double) -> Color {
        if t < 72 { return .blue }
        if t < 78 { return .green }
        if t < 84 { return Color(red: 0.1, green: 0.75, blue: 0.4) }
        return .orange
    }

    var body: some View {
        CardView(title: "Water Temp", systemImage: "thermometer.medium") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", vm.weather?.waterTempF ?? 0.0))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(tempColor)
                        Text("F")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        if vm.waterTempEstimated { EstimatedBadge() }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(tempNote)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                        Text("Air: \(String(format: "%.0f", vm.weather?.airTempF ?? 0.0))F")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if !vm.dailySummaries.isEmpty {
                    Divider()
                    Text("3-DAY FORECAST")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)

                    ForEach(vm.dailySummaries) { day in
                        HStack(spacing: 10) {
                            Text(day.dayLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 60, alignment: .leading)

                            GeometryReader { geo in
                                let minT = 65.0
                                let maxT = 95.0
                                let range = maxT - minT
                                let startFrac = (day.minWaterTempF - minT) / range
                                let endFrac = (day.maxWaterTempF - minT) / range
                                let barStart = CGFloat(max(0, startFrac)) * geo.size.width
                                let barEnd = CGFloat(min(1, endFrac)) * geo.size.width

                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(.systemGray5))
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(LinearGradient(
                                            colors: [colorForTemp(day.minWaterTempF), colorForTemp(day.maxWaterTempF)],
                                            startPoint: .leading, endPoint: .trailing
                                        ))
                                        .frame(width: max(6, barEnd - barStart))
                                        .offset(x: barStart)
                                }
                                .frame(height: 8)
                                .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 16)

                            Text(String(format: "%.0f-%.0fF", day.minWaterTempF, day.maxWaterTempF))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(colorForTemp(day.avgWaterTempF))
                                .frame(width: 65, alignment: .trailing)

                            if day.waterTempEstimated {
                                EstimatedBadge()
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Pressure Card

struct PressureCardView: View {
    @EnvironmentObject var vm: FishingViewModel

    var pressureColor: Color {
        guard let rate = vm.weather?.pressureChangeRate else { return .gray }
        if rate < -0.5 { return .green }
        if rate < -0.1 { return Color(red: 0.2, green: 0.7, blue: 0.4) }
        return Color(.systemGray)
    }

    var trendIcon: String {
        guard let rate = vm.weather?.pressureChangeRate else { return "minus" }
        if rate < -0.1 { return "arrow.down.right" }
        if rate > 0.1 { return "arrow.up.right" }
        return "arrow.right"
    }

    var trendNote: String {
        guard let rate = vm.weather?.pressureChangeRate else { return "" }
        if rate < -1.0 { return "Dropping fast - fish feeding" }
        if rate < -0.5 { return "Dropping - increased activity" }
        if rate < -0.1 { return "Slight drop - favorable" }
        if rate > 0.5 { return "Rising - fish settling" }
        if rate > 0.1 { return "Rising slightly" }
        return "Stable - normal conditions"
    }

    private func trendColor(for rate: Double) -> Color {
        if rate < -0.5 { return .green }
        if rate < -0.1 { return Color(red: 0.2, green: 0.7, blue: 0.4) }
        if rate > 0.5 { return .orange }
        return Color(.systemGray)
    }

    var body: some View {
        CardView(title: "Pressure", systemImage: "barometer") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.0f", vm.weather?.pressureHpa ?? 0.0))
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .foregroundColor(pressureColor)
                            Text("hPa")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if vm.weatherIsDemo { EstimatedBadge() }
                        }
                        HStack(spacing: 4) {
                            Image(systemName: trendIcon)
                                .font(.caption)
                                .foregroundColor(pressureColor)
                            Text(String(format: "%+.1f hPa/hr", vm.weather?.pressureChangeRate ?? 0.0))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(pressureColor)
                        }
                    }
                    Spacer()
                    Text(trendNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }

                if !vm.dailySummaries.isEmpty {
                    Divider()
                    Text("3-DAY FORECAST")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)

                    ForEach(vm.dailySummaries) { day in
                        HStack(spacing: 10) {
                            Text(day.dayLabel)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .frame(width: 60, alignment: .leading)

                            HStack(alignment: .bottom, spacing: 1) {
                                let pressures = day.hourlyPressure.map(\.1)
                                let minP = (pressures.min() ?? 1010) - 1
                                let maxP = (pressures.max() ?? 1020) + 1
                                let range = max(maxP - minP, 1)
                                ForEach(day.hourlyPressure, id: \.0) { item in
                                    let normalized = (item.1 - minP) / range
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(trendColor(for: day.pressureTrend).opacity(0.6))
                                        .frame(width: 3, height: max(2, CGFloat(normalized) * 24))
                                }
                            }
                            .frame(height: 24)

                            Spacer()

                            Text(String(format: "%.0f", day.avgPressureHpa))
                                .font(.caption.bold())

                            HStack(spacing: 2) {
                                Image(systemName: day.pressureTrend < -0.5 ? "arrow.down.right" :
                                        day.pressureTrend > 0.5 ? "arrow.up.right" : "arrow.right")
                                    .font(.system(size: 9))
                                Text(String(format: "%+.1f", day.pressureTrend))
                                    .font(.caption2)
                            }
                            .foregroundColor(trendColor(for: day.pressureTrend))
                            .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}
