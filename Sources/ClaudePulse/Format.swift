import Foundation

enum Format {
    static func countdown(to date: Date, from now: Date = Date()) -> String {
        duration(max(0, date.timeIntervalSince(now)))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }

    static func ago(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let s = now.timeIntervalSince(date)
        if s < 45 { return "just now" }
        return duration(s) + " ago"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
    private static let dayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return f
    }()

    /// Local reset time: "5:30 PM" today, otherwise "Tue 5:30 PM".
    static func resetTime(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? timeFormatter.string(from: date) : dayTimeFormatter.string(from: date)
    }

    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            let m = Double(n) / 1_000_000
            return m >= 10 || m == m.rounded() ? "\(Int(m.rounded()))M" : String(format: "%.1fM", m)
        }
        if n >= 1_000 { return "\(Int((Double(n) / 1_000).rounded()))k" }
        return "\(n)"
    }

    static func cost(_ usd: Double) -> String {
        usd < 10 ? String(format: "$%.2f", usd) : String(format: "$%.0f", usd)
    }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }
}
