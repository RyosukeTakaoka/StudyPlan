import Foundation

/// 同期の対象になるモデルの共通ルール。
/// - id は端末で作る UUID
/// - 変更したら updatedAt を更新する（競合したら新しい方を採用するため）
/// - 削除は消さずに deletedAt を付ける（論理削除）
protocol SyncTracked: AnyObject {
    var id: UUID { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

extension SyncTracked {
    var isAlive: Bool { deletedAt == nil }

    func touch(_ date: Date = .now) {
        updatedAt = date
    }

    func softDelete(_ date: Date = .now) {
        deletedAt = date
        updatedAt = date
    }
}

extension Sequence where Element: SyncTracked {
    /// 論理削除されていないものだけ
    var alive: [Element] { filter(\.isAlive) }
}
