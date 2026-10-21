import SwiftUI
import UIKit

/// 見た目の約束ごと。
///
/// 個性を出すのは次の3か所だけ。
/// 1. アクセント色（ボタン・「今」の印・選択状態をこの1色に統一）
/// 2. 完了の演出（`CompletionStroke`）
/// 3. 「今のブロック」の印（`MarkerUnderline`）
/// 演出（2と3）は1画面に1か所まで。設定でまとめて外せる（`Preferences.flourishes`）。
enum Theme {
    /// ホワイトボードマーカーのような深い青。
    /// 値は Shared/Assets.xcassets/AccentColor（ライト #2B4C9B／ダーク #5E7FD6）。
    static let accent = Color.accentColor

    static let cardCornerRadius: CGFloat = 14
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let screenBackground = Color(uiColor: .systemGroupedBackground)
    static let imagePlaceholder = Color(uiColor: .tertiarySystemFill)
}

/// 文字の大きさはすべてテキストスタイルで指定する（固定サイズは使わない）。
///
/// 下限：一覧と補足文字には `.caption` / `.caption2` を使わず、最小でも `.footnote` にする。
/// さらに `readableFloor()` を付けた場所は、端末の文字サイズを小さくしても標準サイズより小さくならない。
enum TextRole {
    /// 「今日の流れ」などの一覧の行
    static let listRow: Font = .subheadline
    /// 補足文字（件数、撮影時刻、注意書きなど）
    static let note: Font = .footnote
    /// これより小さい文字サイズにはしない
    static let minimumSize: DynamicTypeSize = .large
}

extension View {
    /// 文字が小さくなりすぎないよう、Dynamic Type の下限を決める
    func readableFloor() -> some View {
        dynamicTypeSize(TextRole.minimumSize...)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// ライトとダークで値を切り替える色
    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}
