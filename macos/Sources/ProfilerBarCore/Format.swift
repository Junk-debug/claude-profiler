import Foundation

/// Every rule here has a twin in `src/tui/format.ts`, and the two test suites
/// assert the same cases: the CLI and this app render the same profile
/// artifact, so a figure that reads "1m 20s" in one and "1m20s" in the other
/// is the same number pretending to be two.
public enum Format {
    /// 950 → "950", 88_295 → "88k", 1_576_617 → "1.6M".
    public static func tokens(_ value: Int) -> String {
        let abs = Swift.abs(value)
        switch abs {
        case ..<1_000:
            return "\(value)"
        case ..<10_000:
            return String(format: "%.1fk", Double(value) / 1_000)
        case ..<1_000_000:
            return "\(Int((Double(value) / 1_000).rounded()))k"
        case ..<10_000_000:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        default:
            return "\(Int((Double(value) / 1_000_000).rounded()))M"
        }
    }

    /// 42 → "42s", 185 → "3m", 3_900 → "1h 5m", 140_520 → "1d 15h".
    public static func duration(seconds: Double) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total)s" }
        if total < 3_600 { return "\(total / 60)m" }
        if total < 86_400 {
            let hours = total / 3_600
            let minutes = (total % 3_600) / 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        return hours == 0 ? "\(days)d" : "\(days)d \(hours)h"
    }

    /// 240 → "240ms", 3_542 → "3.5s", 80_000 → "1m 20s", 3_900_000 → "1h 5m".
    /// Keeps the seconds a profile reader wants, where `duration` rounds to
    /// whole minutes for "how long ago" labels.
    public static func ms(_ value: Double) -> String {
        if value < 1_000 { return "\(Int(value.rounded()))ms" }
        if value < 10_000 { return String(format: "%.1fs", value / 1_000) }
        let seconds = Int(value / 1_000)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 {
            let rest = seconds % 60
            return rest == 0 ? "\(seconds / 60)m" : "\(seconds / 60)m \(rest)s"
        }
        return duration(seconds: Double(seconds))
    }

    /// The same, for the artifact fields that report an unmeasurable span as
    /// null rather than as zero.
    public static func ms(_ value: Double?) -> String {
        value.map(ms) ?? "—"
    }

    /// Output tokens per second. A decimal only where it separates a stall
    /// from a crawl (under ten), none above it, where three digits of
    /// precision on a rate that swings by 50% between requests is false
    /// confidence: 0.2 → "0.2", 118.34 → "118".
    public static func rate(_ tokensPerSec: Double?) -> String {
        guard let tokensPerSec, tokensPerSec.isFinite else { return "—" }
        return String(format: tokensPerSec >= 10 ? "%.0f" : "%.1f", tokensPerSec)
    }

    /// Binary units, named as such: 820 → "820 B", 819_043 → "800 KiB",
    /// 5_400_000 → "5.1 MiB".
    public static func bytes(_ value: Double) -> String {
        if value < 1_024 { return "\(Int(value.rounded())) B" }
        if value < 1_024 * 1_024 { return "\(Int((value / 1_024).rounded())) KiB" }
        return String(format: "%.1f MiB", value / (1_024 * 1_024))
    }

    /// The same, for the artifact fields that report an unknown size as null.
    public static func bytes(_ value: Double?) -> String {
        value.map(bytes) ?? "—"
    }

    /// Takes a ratio, the way every `pct…` field in the profile artifact is
    /// stored: 0.0197 → "2.0%", 0.45 → "45%".
    public static func percent(ratio: Double) -> String {
        let value = ratio * 100
        return value >= 10 ? String(format: "%.0f%%", value) : String(format: "%.1f%%", value)
    }

    /// Money. Cents for anything a person would recognise as a price, four
    /// decimals below a cent — `cacheWaste` reports real amounts that round to
    /// $0.00 and would otherwise read as free.
    public static func usd(_ value: Double) -> String {
        if value > 0, value < 0.01 { return String(format: "$%.4f", value) }
        return String(format: "$%.2f", value)
    }

    /// The same, for the many artifact fields that report an absent amount as
    /// null rather than as zero.
    public static func usd(_ value: Double?) -> String {
        value.map(usd) ?? "—"
    }

    /// Local wall-clock, not UTC: "2026-01-02 03:04". A timestamp the reader is
    /// meant to recognise as "when I was at my desk" has to be in the clock
    /// they were reading at the time.
    public static func dateTime(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter.parser.dateOrPlain(from: iso) else { return "—" }
        return DateFormatter.stamp.string(from: date)
    }

    /// "21:16:05", for table rows inside one session, where every line carries
    /// the same date.
    public static func clock(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter.parser.dateOrPlain(from: iso) else { return "—" }
        return DateFormatter.clock.string(from: date)
    }

    /// "claude-opus-5" → "Opus 5", "claude-sonnet-4-5-20250929" → "Sonnet 4.5".
    public static func model(_ id: String) -> String {
        let base = id.split(separator: "[").first.map(String.init) ?? id
        var parts = base.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().joined(separator: ".")
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version)"
    }
}

public extension ISO8601DateFormatter {
    /// The artifact writes `toISOString()`, which always carries milliseconds,
    /// but hook payloads and CC's own records do not always agree — so a
    /// timestamp without them parses too rather than rendering as "—".
    static let parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plainParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func dateOrPlain(from iso: String) -> Date? {
        date(from: iso) ?? ISO8601DateFormatter.plainParser.date(from: iso)
    }
}

public extension DateFormatter {
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
