import Foundation
import SwiftData
import UIKit

/// 写真から切り出した1ブロック分のカード。筆跡画像が主役で、文字起こしは裏方。
@Model
final class Card: SyncTracked {
    var id: UUID = UUID()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var snapshot: Snapshot?
    /// 補正後の写真の中での位置（0〜1、左上が原点）
    var cropX: Double = 0
    var cropY: Double = 0
    var cropWidth: Double = 1
    var cropHeight: Double = 1
    /// 筆跡画像。App Intents から文字だけで作ったカードでは nil。
    @Attribute(.externalStorage) var handwriting: Data?
    var transcription: String = ""
    var start: Date = Date()
    var end: Date = Date()
    /// 対象日のキー "YYYY-MM-DD"（Asia/Tokyo）。サーバーの cards.date と同じ。
    var dayKey: String = ""
    var categoryRaw: String = "study"
    var statusRaw: String = "planned"
    /// 持ち越した回数（持ち越し元から引き継ぎ、「持ち越し」にすると1増える）
    var carriedOverCount: Int = 0
    /// 持ち越し元のカードの id
    var carriedFromCardID: UUID?
    /// 文字認識の行（検索のハイライト用）を JSON で持つ
    var linesData: Data?

    @Relationship(deleteRule: .cascade, inverse: \TimeLog.card)
    var timeLogs: [TimeLog]? = []

    init(
        handwriting: Data?,
        crop: NormalizedRect,
        transcription: String,
        lines: [RecognizedLine],
        start: Date,
        end: Date,
        category: BlockCategory
    ) {
        self.id = UUID()
        self.handwriting = handwriting
        self.cropX = crop.x
        self.cropY = crop.y
        self.cropWidth = crop.width
        self.cropHeight = crop.height
        self.transcription = transcription
        self.linesData = try? JSONEncoder().encode(lines)
        self.start = start
        self.end = end
        self.dayKey = TimeText.dayKey(start)
        self.categoryRaw = category.rawValue
        self.updatedAt = .now
    }
}

extension Card {
    var category: BlockCategory {
        get { BlockCategory(rawValue: categoryRaw) ?? .study }
        set { categoryRaw = newValue.rawValue; touch() }
    }

    var status: CardStatus { CardStatus(rawValue: statusRaw) ?? .planned }

    var crop: NormalizedRect {
        NormalizedRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
    }

    var lines: [RecognizedLine] {
        guard let linesData else { return [] }
        return (try? JSONDecoder().decode([RecognizedLine].self, from: linesData)) ?? []
    }

    var hasHandwritingImage: Bool { handwriting != nil }

    var handwritingImage: UIImage? {
        ImageCache.image(for: "card-\(id.uuidString)-\(handwriting?.count ?? 0)") { handwriting }
    }

    /// 文字起こしの1行目（先頭の時刻は除く）。なければ区分名。
    var title: String { TimeParser.title(from: transcription) ?? category.label }

    var timeRangeText: String { TimeText.range(start, end) }

    func contains(_ date: Date) -> Bool { start <= date && date < end }

    var aliveTimeLogs: [TimeLog] {
        (timeLogs ?? []).alive.sorted { $0.actualStart < $1.actualStart }
    }

    /// 記録中（終了していない）の時間ログ
    var openTimeLog: TimeLog? { aliveTimeLogs.last { $0.actualEnd == nil } }

    var actualStart: Date? { aliveTimeLogs.first?.actualStart }
    var actualEnd: Date? { aliveTimeLogs.compactMap(\.actualEnd).max() }

    /// 状態を変える。持ち越しにすると回数が1増え、持ち越しをやめると1戻る。
    func setStatus(_ newStatus: CardStatus, at date: Date = .now) {
        let old = status
        guard old != newStatus else { return }
        if newStatus == .carried { carriedOverCount += 1 }
        if old == .carried { carriedOverCount = max(0, carriedOverCount - 1) }
        statusRaw = newStatus.rawValue
        touch(date)
    }

    /// ボタンを押したとき：同じ状態をもう一度押したら「予定」に戻す（取り消し）。変更後の状態を返す。
    @discardableResult
    func toggle(_ tapped: CardStatus) -> CardStatus {
        let newStatus: CardStatus = status == tapped ? .planned : tapped
        setStatus(newStatus)
        return newStatus
    }

    func setTimes(start: Date, end: Date) {
        self.start = start
        self.end = max(end, start)
        dayKey = TimeText.dayKey(start)
        touch()
    }
}
