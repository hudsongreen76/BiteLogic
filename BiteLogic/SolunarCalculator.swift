import Foundation

// MARK: - Solunar Period

struct SolunarPeriod: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let isMajor: Bool

    var label: String { isMajor ? "Major" : "Minor" }
    var icon: String { isMajor ? "moon.stars.fill" : "moon.fill" }

    func overlaps(start blockStart: Date, end blockEnd: Date) -> Bool {
        start < blockEnd && end > blockStart
    }

    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
}

// MARK: - Solunar Calculator
//
// Solunar theory: fish feed most actively during four daily periods driven by
// the moon's position relative to the observer.
//
//   Major periods (~2 hrs): when moon is directly overhead (upper transit)
//                            or directly underfoot (lower transit)
//   Minor periods (~1 hr):  when moon is rising or setting
//
// Transit time shifts by ~50 minutes per solar day relative to solar noon,
// because the lunar day is ~24h 50m (longer than the solar day).
// At new moon the upper transit is near solar noon; at full moon, near midnight.

struct SolunarCalculator {

    // Reference new moon: Jan 6, 2000 18:14 UTC
    private static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440.0)
    private static let synodicMonth: TimeInterval = 29.530_588_853 * 86_400.0
    /// Lunar day ≈ 24 h 50 min 28 s
    private static let lunarDay: TimeInterval = 24.8417 * 3_600.0

    // MARK: - Public API

    /// Returns all solunar periods for the calendar day containing `date` in `timezone`.
    static func periods(for date: Date, timezone: TimeZone) -> [SolunarPeriod] {
        var cal = Calendar.current
        cal.timeZone = timezone
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay   = startOfDay.addingTimeInterval(86_400)

        // Moon age in days since last new moon
        let elapsed = date.timeIntervalSince(referenceNewMoon)
        var moonAge = elapsed.truncatingRemainder(dividingBy: synodicMonth)
        if moonAge < 0 { moonAge += synodicMonth }
        let moonAgeDays = moonAge / 86_400.0

        // Upper transit = local noon + (50 min × moonAgeDays), wrapped to [0, 24h)
        let rawOffset = (12.0 * 3_600 + moonAgeDays * 50.0 * 60.0)
            .truncatingRemainder(dividingBy: 86_400)
        let upperTransit = startOfDay.addingTimeInterval(rawOffset)

        // Lower transit = upper + half a lunar day
        let lowerTransit = upperTransit.addingTimeInterval(lunarDay / 2.0)

        // Minor events: moon rise/set ≈ ¼ lunar day from each transit
        let moonset  = upperTransit.addingTimeInterval(lunarDay / 4.0)
        let moonrise = upperTransit.addingTimeInterval(-lunarDay / 4.0)

        let majorDur: TimeInterval = 7_200   // 2 hours
        let minorDur: TimeInterval = 3_600   // 1 hour

        let candidates: [(center: Date, major: Bool)] = [
            (upperTransit, true),
            (lowerTransit, true),
            (moonrise, false),
            (moonset, false),
            // Also check yesterday's events that bleed into today
            (upperTransit.addingTimeInterval(-lunarDay), true),
            (lowerTransit.addingTimeInterval(-lunarDay), true),
            (moonrise.addingTimeInterval(-lunarDay), false),
            (moonset.addingTimeInterval(-lunarDay), false),
            // And tomorrow's that start today
            (upperTransit.addingTimeInterval(lunarDay), true),
            (lowerTransit.addingTimeInterval(lunarDay), true),
            (moonrise.addingTimeInterval(lunarDay), false),
            (moonset.addingTimeInterval(lunarDay), false),
        ]

        var periods: [SolunarPeriod] = []
        var seen: [Date] = []

        for (center, isMajor) in candidates {
            let half = (isMajor ? majorDur : minorDur) / 2.0
            let s = center.addingTimeInterval(-half)
            let e = center.addingTimeInterval(half)

            // Must overlap today
            guard e > startOfDay && s < endOfDay else { continue }
            // Deduplicate (periods within 1 h of each other)
            guard !seen.contains(where: { abs($0.timeIntervalSince(center)) < 3_600 }) else { continue }

            seen.append(center)
            periods.append(SolunarPeriod(start: s, end: e, isMajor: isMajor))
        }

        return periods.sorted { $0.start < $1.start }
    }

    /// Returns solunar periods that overlap with the given time block.
    static func periodsOverlapping(blockStart: Date, blockEnd: Date, timezone: TimeZone) -> [SolunarPeriod] {
        periods(for: blockStart, timezone: timezone)
            .filter { $0.overlaps(start: blockStart, end: blockEnd) }
    }

    /// Returns the active solunar period at `date`, if any.
    static func activePeriod(at date: Date, timezone: TimeZone) -> SolunarPeriod? {
        periods(for: date, timezone: timezone).first { $0.contains(date) }
    }

    /// Returns today's upcoming solunar periods (end > now).
    static func upcomingPeriods(timezone: TimeZone) -> [SolunarPeriod] {
        let now = Date()
        return periods(for: now, timezone: timezone).filter { $0.end > now }
    }

    /// Formats a period's time range in the given timezone. e.g. "6:30am–7:30am"
    static func formatPeriod(_ period: SolunarPeriod, timezone: TimeZone) -> String {
        let f = DateFormatter()
        f.timeZone = timezone
        f.dateFormat = "h:mma"
        f.amSymbol = "am"
        f.pmSymbol = "pm"
        return "\(f.string(from: period.start))–\(f.string(from: period.end))"
    }
}
