import Foundation

/// 文字起こしから時刻やタイトルを取り出す
enum TimeParser {
    private static let timePattern = #"([01]?\d|2[0-3])\s*[:：]\s*([0-5]\d)"#
    private static let timeRegex = try! NSRegularExpression(pattern: timePattern)
    /// 行頭の「07:00」や「07:00-08:30」
    private static let leadingTimeRegex = try! NSRegularExpression(
        pattern: #"^\s*"# + timePattern + #"(\s*[-–—~〜～]\s*"# + timePattern + #")?\s*"#
    )

    /// 全角の英数字・記号（！〜～）と全角スペースだけを半角にそろえる（文字認識が全角で返すことがあるため）。
    /// カタカナや句読点は変えない。
    static func normalize(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF01...0xFF5E:
                scalars.append(Unicode.Scalar(scalar.value - 0xFEE0) ?? scalar)
            case 0x3000:
                scalars.append(" ")
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// 文字列の中の最初の時刻を、day の日付に合わせて返す
    static func firstTime(in text: String, on day: Date) -> Date? {
        let normalized = normalize(text)
        let ns = normalized as NSString
        guard let match = timeRegex.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length)),
              let hour = Int(ns.substring(with: match.range(at: 1))),
              let minute = Int(ns.substring(with: match.range(at: 2))) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    static func startsWithTime(_ text: String) -> Bool {
        let normalized = normalize(text)
        return leadingTimeRegex.firstMatch(in: normalized, range: NSRange(location: 0, length: (normalized as NSString).length)) != nil
    }

    /// 先頭の時刻を除いた、最初の空でない行
    static func title(from transcription: String) -> String? {
        for line in transcription.split(whereSeparator: \.isNewline) {
            let normalized = normalize(String(line))
            let ns = normalized as NSString
            let stripped = leadingTimeRegex.stringByReplacingMatches(
                in: normalized, range: NSRange(location: 0, length: ns.length), withTemplate: ""
            ).trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { return stripped }
        }
        return nil
    }
}
