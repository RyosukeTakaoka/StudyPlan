import Foundation
import SwiftData

/// 実際に取り組んだ時間（開始・終了をワンタップで記録）
@Model
final class TimeLog: SyncTracked {
    var id: UUID = UUID()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var card: Card?
    var actualStart: Date = Date()
    var actualEnd: Date?

    init(actualStart: Date, actualEnd: Date? = nil) {
        self.id = UUID()
        self.actualStart = actualStart
        self.actualEnd = actualEnd
        self.updatedAt = .now
    }
}

extension Card {
    /// 開始を記録する。すでに記録中なら何もしない。
    func startTimeLog(in context: ModelContext, at date: Date = .now) {
        guard openTimeLog == nil else { return }
        let log = TimeLog(actualStart: date)
        context.insert(log)
        log.card = self
        touch(date)
    }

    /// 終了を記録する。記録中のものがなければ、予定の開始から今までを1件作る。
    func endTimeLog(in context: ModelContext, at date: Date = .now) {
        if let open = openTimeLog {
            open.actualEnd = max(date, open.actualStart)
            open.touch(date)
        } else {
            let log = TimeLog(actualStart: min(start, date), actualEnd: date)
            context.insert(log)
            log.card = self
        }
        touch(date)
    }
}
