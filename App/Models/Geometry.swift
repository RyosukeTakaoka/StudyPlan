import CoreGraphics
import Foundation

/// 画像に対する位置（0〜1）。原点は左上。
struct NormalizedRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    var maxX: Double { x + width }
    var maxY: Double { y + height }

    func cgRect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: width * size.width, height: height * size.height)
    }

    func union(_ other: NormalizedRect) -> NormalizedRect {
        let minX = min(x, other.x), minY = min(y, other.y)
        return NormalizedRect(x: minX, y: minY, width: max(maxX, other.maxX) - minX, height: max(maxY, other.maxY) - minY)
    }

    /// 外側に広げて、0〜1 に収める
    func padded(dx: Double, dy: Double) -> NormalizedRect {
        let minX = max(0, x - dx), minY = max(0, y - dy)
        let maxX = min(1, self.maxX + dx), maxY = min(1, self.maxY + dy)
        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// container の中での相対位置に変換する
    func relative(to container: NormalizedRect) -> NormalizedRect {
        guard container.width > 0, container.height > 0 else { return self }
        return NormalizedRect(
            x: (x - container.x) / container.width,
            y: (y - container.y) / container.height,
            width: width / container.width,
            height: height / container.height
        )
    }
}

/// 文字認識の結果1行分。位置はカード画像に対する相対位置。
struct RecognizedLine: Codable, Hashable {
    var text: String
    var confidence: Float
    var rect: NormalizedRect
}
