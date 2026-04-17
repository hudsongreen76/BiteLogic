import Foundation

struct TideStageCalculator {

    /// Derive tide stage at a specific time by interpolating within nearby readings.
    /// Samples multiple points around `targetTime` to avoid the "no movement between endpoints" bug.
    static func tideStage(at targetTime: Date, readings: [TideReading]) -> TideStage {
        let sorted = readings.sorted { $0.time < $1.time }
        guard sorted.count >= 2 else { return .slack }

        let rate = changeRate(at: targetTime, readings: sorted)

        // Slack threshold: < 0.02 ft/hr
        if abs(rate) < 0.02 {
            return .slack
        }
        return rate > 0 ? .incoming : .outgoing
    }

    /// Compute tide change rate (ft/hr) at a specific time using interpolation
    /// across multiple sample points to capture movement within a block.
    static func changeRate(at targetTime: Date, readings: [TideReading]) -> Double {
        let sorted = readings.sorted { $0.time < $1.time }
        guard sorted.count >= 2 else { return 0 }

        // Sample heights at 15-minute intervals around the target time
        let sampleOffsets: [TimeInterval] = [-900, -450, 0, 450, 900] // -15min to +15min
        var samples: [(time: Date, height: Double)] = []

        for offset in sampleOffsets {
            let t = targetTime.addingTimeInterval(offset)
            if let h = interpolatedHeight(at: t, readings: sorted) {
                samples.append((t, h))
            }
        }

        guard samples.count >= 2 else { return 0 }

        // Linear regression slope across samples
        let n = Double(samples.count)
        let refTime = samples[0].time.timeIntervalSince1970
        let xs = samples.map { ($0.time.timeIntervalSince1970 - refTime) / 3600.0 } // hours
        let ys = samples.map { $0.height }

        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)

        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-10 else { return 0 }

        return (n * sumXY - sumX * sumY) / denom // ft/hr
    }

    /// Interpolate tide height at an arbitrary time from hourly readings.
    static func interpolatedHeight(at time: Date, readings: [TideReading]) -> Double? {
        let sorted = readings.sorted { $0.time < $1.time }
        guard let first = sorted.first, let last = sorted.last else { return nil }

        if time <= first.time { return first.heightFt }
        if time >= last.time { return last.heightFt }

        guard let afterIdx = sorted.firstIndex(where: { $0.time >= time }) else { return nil }
        if afterIdx == 0 { return sorted[0].heightFt }

        let before = sorted[afterIdx - 1]
        let after = sorted[afterIdx]
        let interval = after.time.timeIntervalSince(before.time)
        guard interval > 0 else { return before.heightFt }

        let fraction = time.timeIntervalSince(before.time) / interval
        return before.heightFt + fraction * (after.heightFt - before.heightFt)
    }

    /// Get tide stage and change rate for a 2-hour forecast block.
    static func blockTideInfo(blockStart: Date, blockEnd: Date, readings: [TideReading]) -> (stage: TideStage, changeRate: Double, height: Double) {
        let midpoint = blockStart.addingTimeInterval(blockEnd.timeIntervalSince(blockStart) / 2)
        let stage = tideStage(at: midpoint, readings: readings)
        let rate = changeRate(at: midpoint, readings: readings)
        let height = interpolatedHeight(at: midpoint, readings: readings) ?? 0
        return (stage, rate, height)
    }
}
