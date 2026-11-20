import Foundation

public enum Streak {
    /// Consecutive local days with at least one scored drill, ending today.
    /// A streak with nothing yet today still counts up to yesterday, so it doesn't reset at midnight.
    public static func days(sessionDates: [Date], today: Date, calendar: Calendar = .current) -> Int {
        let days = Set(sessionDates.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: today)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
