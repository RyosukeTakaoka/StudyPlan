import Foundation
import SwiftData
import UIKit

/// ある日のボードの写真1枚
@Model
final class Snapshot: SyncTracked {
    var id: UUID = UUID()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var board: Board?
    var capturedAt: Date = Date()
    /// 対象日（その日の0時）
    var targetDate: Date = Date()
    /// 対象日のキー "YYYY-MM-DD"（Asia/Tokyo）。サーバーの snapshots.target_date と同じ。
    var dayKey: String = ""
    @Attribute(.externalStorage) var originalPhoto: Data?
    /// 台形補正後の写真
    @Attribute(.externalStorage) var correctedPhoto: Data?
    var didCorrectPerspective: Bool = false
    /// 文字認識の全文
    var fullText: String = ""
    /// 「サンプルデータを入れる」で作ったもの
    var isSample: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Card.snapshot)
    var cards: [Card]? = []

    init(capturedAt: Date, targetDate: Date) {
        self.id = UUID()
        self.capturedAt = capturedAt
        // 日付は Asia/Tokyo で決める（サーバー・AI と同じ日付キーにそろえる）
        self.targetDate = TimeText.tokyoCalendar.startOfDay(for: targetDate)
        self.dayKey = TimeText.dayKey(targetDate)
        self.updatedAt = .now
    }
}

extension Snapshot {
    /// 論理削除されていないカードを時刻順に
    var sortedCards: [Card] {
        (cards ?? []).alive.sorted { $0.start < $1.start }
    }

    var correctedImage: UIImage? {
        ImageCache.image(for: "snapshot-\(id.uuidString)-\(correctedPhoto?.count ?? originalPhoto?.count ?? 0)") { correctedPhoto ?? originalPhoto }
    }

    /// 写真とそのカード・時間ログをまとめて論理削除する
    func softDeleteWithCards(_ date: Date = .now) {
        for card in cards ?? [] where card.isAlive {
            for log in card.timeLogs ?? [] where log.isAlive { log.softDelete(date) }
            card.softDelete(date)
        }
        softDelete(date)
    }

    /// その日の最新の写真（snapshots は撮影日時の新しい順に並んでいる前提）
    static func latest(on day: Date, in snapshots: [Snapshot]) -> Snapshot? {
        let key = TimeText.dayKey(day)
        return snapshots.first { $0.isAlive && $0.dayKey == key }
    }
}
