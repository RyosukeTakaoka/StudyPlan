import Foundation

/// カードの状態。rawValue はサーバー（D1 の cards.status）と同じ文字列。
enum CardStatus: String, CaseIterable, Identifiable, Codable {
    case planned
    case done
    case notDone = "not_done"
    case carried
    case skipped

    var id: Self { self }

    /// 実績として記録できるもの（ボタンの並び順）
    static let recordable: [CardStatus] = [.done, .notDone, .carried, .skipped]

    var label: String {
        switch self {
        case .planned: return "予定"
        case .done: return "完了"
        case .notDone: return "未完了"
        case .carried: return "持ち越し"
        case .skipped: return "スキップ"
        }
    }

    var symbol: String {
        switch self {
        case .planned: return "clock"
        case .done: return "checkmark"
        case .notDone: return "circle"
        case .carried: return "arrow.right"
        case .skipped: return "minus"
        }
    }
}
