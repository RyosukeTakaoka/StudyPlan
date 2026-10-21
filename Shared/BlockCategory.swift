import SwiftUI
import UIKit

/// ブロックの区分。色・SFシンボル・文字ラベルの3点で区別する（色だけに頼らない）。
/// rawValue はサーバー（D1 の cards.category）と同じ文字列。
enum BlockCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case study
    case nap
    case game
    case programming
    case travel
    case fixed
    case rest

    var id: Self { self }

    var label: String {
        switch self {
        case .study: return "勉強"
        case .nap: return "仮眠"
        case .game: return "ゲーム"
        case .programming: return "プログラミング"
        case .travel: return "移動"
        case .fixed: return "固定予定"
        case .rest: return "休憩"
        }
    }

    var symbol: String {
        switch self {
        case .study: return "book.fill"
        case .nap: return "moon.zzz.fill"
        case .game: return "gamecontroller.fill"
        case .programming: return "chevron.left.forwardslash.chevron.right"
        case .travel: return "figure.walk"
        case .fixed: return "pin.fill"
        case .rest: return "cup.and.saucer.fill"
        }
    }

    /// 彩度を抑えた色。筆跡画像より目立たせないため、アクセント色の青とも離してある。
    var color: Color { Color(uiColor: uiColor) }

    private var uiColor: UIColor {
        switch self {
        case .study: return .dynamic(light: 0x5A6A85, dark: 0xA3B0C8)
        case .nap: return .dynamic(light: 0x766C93, dark: 0xB3AACB)
        case .game: return .dynamic(light: 0x8E6470, dark: 0xCDA3AE)
        case .programming: return .dynamic(light: 0x4F7A6E, dark: 0x95BFB2)
        case .travel: return .dynamic(light: 0x857348, dark: 0xC8B78C)
        case .fixed: return .dynamic(light: 0x6B6B70, dark: 0xAEAEB4)
        case .rest: return .dynamic(light: 0x8A6A52, dark: 0xC9AA92)
        }
    }

    /// 文字起こしから区分を推測する。外れても確認画面で直せる。
    static func guess(from text: String) -> BlockCategory {
        let keywords: [(BlockCategory, [String])] = [
            (.rest, ["休憩", "休み", "昼食", "ごはん", "ご飯"]),
            (.nap, ["仮眠", "昼寝"]),
            (.game, ["ゲーム"]),
            (.programming, ["プログラ", "コード", "開発", "アプリ"]),
            (.travel, ["移動", "通学", "通勤"]),
            (.fixed, ["授業", "会議", "バイト", "予約"])
        ]
        for (category, words) in keywords where words.contains(where: { text.contains($0) }) {
            return category
        }
        return .study
    }
}

/// 区分のラベル（アイコン＋文字＋色）
struct CategoryLabel: View {
    let category: BlockCategory

    var body: some View {
        Label(category.label, systemImage: category.symbol)
            .labelStyle(.titleAndIcon)
            .font(TextRole.note.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(category.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(category.color.opacity(0.14), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("区分：\(category.label)")
    }
}
