import Foundation
import SwiftData
import UIKit

/// 動作確認用のサンプル（今日・昨日・先週）。
/// 筆跡は表示確認用の合成画像なので、実際に使うときは撮影したカード画像に置き換わる。
enum SampleData {
    private struct Block {
        let lines: [String]
        let minutes: Int
        let category: BlockCategory
        var ink: UIColor = UIColor(red: 0.12, green: 0.23, blue: 0.54, alpha: 1)
        var status: CardStatus = .planned
    }

    private static let cardSize = CGSize(width: 900, height: 440)
    private static let redInk = UIColor(red: 0.6, green: 0.29, blue: 0.23, alpha: 1)

    static func insert(into context: ModelContext, now: Date = .now, refreshesWidget: Bool = true) {
        let calendar = Calendar.current
        let board = Board.defaultBoard(in: context)

        // 前に入れたサンプルは消してから入れ直す
        let existing = (try? context.fetch(FetchDescriptor<Snapshot>())) ?? []
        for snapshot in existing where snapshot.isSample && snapshot.isAlive {
            snapshot.softDeleteWithCards()
        }

        // 今日：今の時刻が1件目のブロックに入るように並べる
        let quarter: TimeInterval = 15 * 60
        let floored = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / quarter).rounded(.down) * quarter)
        insertSnapshot(
            blocks: [
                Block(lines: ["鑑定理論", "総則 1〜3"], minutes: 90, category: .study),
                Block(lines: ["過去問", "民法 20問"], minutes: 45, category: .study, ink: redInk),
                Block(lines: ["休憩"], minutes: 15, category: .rest, ink: .darkGray),
                Block(lines: ["アプリ開発", "ウィジェット"], minutes: 60, category: .programming),
                Block(lines: ["仮眠"], minutes: 20, category: .nap, ink: .darkGray)
            ],
            firstStart: max(floored.addingTimeInterval(-30 * 60), calendar.startOfDay(for: now)),
            board: board,
            context: context
        )

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        insertSnapshot(
            blocks: [
                Block(lines: ["過去問", "民法 20問"], minutes: 60, category: .study, ink: redInk, status: .done),
                Block(lines: ["復習・民法総則", "総則 1〜3"], minutes: 45, category: .study, status: .carried),
                Block(lines: ["移動"], minutes: 30, category: .travel, ink: .darkGray, status: .done),
                Block(lines: ["鑑定理論", "各論"], minutes: 90, category: .study, status: .skipped)
            ],
            firstStart: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: yesterday) ?? yesterday,
            board: board,
            context: context
        )

        let lastWeek = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        insertSnapshot(
            blocks: [
                Block(lines: ["鑑定理論", "総則 1〜3"], minutes: 90, category: .study, status: .notDone),
                Block(lines: ["ゲーム"], minutes: 30, category: .game, ink: .darkGray, status: .done),
                Block(lines: ["授業"], minutes: 90, category: .fixed, ink: .darkGray, status: .done)
            ],
            firstStart: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: lastWeek) ?? lastWeek,
            board: board,
            context: context
        )

        try? context.save()
        if refreshesWidget { WidgetSync.refresh(using: context, now: now) }
    }

    private static func insertSnapshot(blocks: [Block], firstStart: Date, board: Board, context: ModelContext) {
        let rendered = blocks.map { renderCard(lines: $0.lines, ink: $0.ink) }
        var drafts: [CardDraft] = []
        var start = firstStart
        for (index, block) in blocks.enumerated() {
            let end = start.addingTimeInterval(TimeInterval(block.minutes * 60))
            let share = 1 / Double(blocks.count)
            drafts.append(CardDraft(
                image: rendered[index].image,
                rect: NormalizedRect(x: 0, y: Double(index) * share, width: 1, height: share),
                transcription: block.lines.joined(separator: "\n"),
                lines: rendered[index].lines,
                start: start,
                end: end,
                category: block.category
            ))
            start = end.addingTimeInterval(15 * 60)
        }
        let cards = SnapshotSaver.save(
            original: nil,
            corrected: composeBoard(rendered.map { $0.image }),
            didCorrect: true,
            day: firstStart,
            capturedAt: firstStart.addingTimeInterval(-20 * 60),
            drafts: drafts,
            board: board,
            isSample: true,
            context: context
        )
        for (card, block) in zip(cards, blocks) where block.status != .planned {
            card.setStatus(block.status)
        }
    }

    /// ボードのカード1枚分の画像を描く（文字はシステムフォント。手書き風フォントは使わない）
    private static func renderCard(lines: [String], ink: UIColor) -> (image: UIImage, lines: [RecognizedLine]) {
        let size = cardSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var recognized: [RecognizedLine] = []
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.92, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            var y: CGFloat = 40
            for (index, line) in lines.enumerated() {
                let font = UIFont.systemFont(ofSize: index == 0 ? 120 : 92, weight: index == 0 ? .semibold : .regular)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: index == 0 ? ink : UIColor(white: 0.15, alpha: 1)
                ]
                let textSize = (line as NSString).size(withAttributes: attributes)
                let origin = CGPoint(x: (size.width - textSize.width) / 2, y: y)
                (line as NSString).draw(at: origin, withAttributes: attributes)
                recognized.append(RecognizedLine(
                    text: line,
                    confidence: 1,
                    rect: NormalizedRect(
                        x: origin.x / size.width, y: origin.y / size.height,
                        width: textSize.width / size.width, height: textSize.height / size.height
                    )
                ))
                y += textSize.height + 16
            }
            let box = UIBezierPath(rect: CGRect(x: 120, y: size.height - 80, width: 44, height: 44))
            box.lineWidth = 5
            UIColor(white: 0.15, alpha: 1).setStroke()
            box.stroke()
        }
        return (image, recognized)
    }

    /// カード画像を縦に並べて、ボード全体の写真の代わりにする
    private static func composeBoard(_ images: [UIImage]) -> UIImage {
        let size = CGSize(width: cardSize.width, height: cardSize.height * CGFloat(images.count))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            for (index, image) in images.enumerated() {
                image.draw(at: CGPoint(x: 0, y: CGFloat(index) * cardSize.height))
                UIColor(white: 0.8, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: CGFloat(index) * cardSize.height, width: size.width, height: 2))
            }
        }
    }
}
