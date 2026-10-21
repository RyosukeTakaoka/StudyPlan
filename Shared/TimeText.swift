import Foundation

/// 時刻と日付の表示・変換。
/// サーバーとのやり取り（日付キー "YYYY-MM-DD" と "HH:mm"）は Asia/Tokyo 固定。
enum TimeText {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    /// 日付キーや "HH:mm" を作るための暦（Asia/Tokyo 固定）
    static let tokyoCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        calendar.locale = Locale(identifier: "ja_JP")
        return calendar
    }()

    private static func formatter(_ format: String, timeZone: TimeZone? = nil) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        if let timeZone { formatter.timeZone = timeZone }
        return formatter
    }

    private static let hourMinute = formatter("HH:mm")
    private static let fullDayFormatter = formatter("yyyy年M月d日（E）")
    private static let monthDayFormatter = formatter("M/d")
    private static let dayKeyFormatter = formatter("yyyy-MM-dd", timeZone: tokyo)
    private static let tokyoHourMinute = formatter("HH:mm", timeZone: tokyo)

    /// 07:00
    static func hm(_ date: Date) -> String { hourMinute.string(from: date) }

    /// 07:00 – 08:30
    static func range(_ start: Date, _ end: Date) -> String { "\(hm(start)) – \(hm(end))" }

    /// 2026年10月21日（水）
    static func fullDay(_ date: Date) -> String { fullDayFormatter.string(from: date) }

    /// 10/21
    static func monthDay(_ date: Date) -> String { monthDayFormatter.string(from: date) }

    /// サーバー・AI向けの日付キー（Asia/Tokyo）。例："2026-10-21"
    static func dayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }

    /// サーバー・AI向けの時刻（Asia/Tokyo）。例："07:00"
    static func wireTime(_ date: Date) -> String { tokyoHourMinute.string(from: date) }

    /// 日付キーと "HH:mm" から Date を作る（Asia/Tokyo）
    static func date(dayKey: String, time: String) -> Date? {
        guard let day = dayKeyFormatter.date(from: dayKey) else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return tokyoCalendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    /// 日付キーからその日の始まり（Asia/Tokyo）
    static func date(dayKey: String) -> Date? { dayKeyFormatter.date(from: dayKey) }
}
