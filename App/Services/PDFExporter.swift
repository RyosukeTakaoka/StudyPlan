import Foundation
import SwiftData
import UIKit

/// 日・週・月のアーカイブを、検索できる PDF に書き出す。
/// 文字起こしを本物の文字として描くので、PDF を開いたアプリで検索できる。
enum PDFExporter {
    enum Range: String, CaseIterable, Identifiable {
        case day, week, month
        var id: Self { self }
        var label: String {
            switch self {
            case .day: return "1日"
            case .week: return "1週間"
            case .month: return "1か月"
            }
        }
        var days: Int {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            }
        }
    }

    /// A4（ポイント）
    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 40

    static func export(range: Range, endingOn day: Date, context: ModelContext) throws -> URL {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: day)
        let startDay = calendar.date(byAdding: .day, value: -(range.days - 1), to: endDay) ?? endDay
        let descriptor = FetchDescriptor<Snapshot>(sortBy: [SortDescriptor(\.targetDate), SortDescriptor(\.capturedAt, order: .reverse)])
        let all = ((try? context.fetch(descriptor)) ?? []).alive
        // 1日1枚（その日の最新）にする
        var seen = Set<String>()
        let snapshots = all.filter { snapshot in
            guard snapshot.targetDate >= startDay, snapshot.targetDate <= endDay else { return false }
            return seen.insert(snapshot.dayKey).inserted
        }

        let fileName = "手書きボード_\(TimeText.dayKey(startDay))_\(TimeText.dayKey(endDay)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        try renderer.writePDF(to: url) { context in
            if snapshots.isEmpty {
                context.beginPage()
                draw("この期間の記録はありません", at: CGPoint(x: margin, y: margin), font: .preferredFont(forTextStyle: .body), width: pageSize.width - margin * 2)
            }
            for snapshot in snapshots {
                drawSnapshot(snapshot, in: context)
            }
        }
        return url
    }

    private static func drawSnapshot(_ snapshot: Snapshot, in context: UIGraphicsPDFRendererContext) {
        let width = pageSize.width - margin * 2
        context.beginPage()
        var y = margin
        let title = "\(TimeText.fullDay(snapshot.targetDate))　\(snapshot.board?.name ?? "")"
        y += draw(title, at: CGPoint(x: margin, y: y), font: .preferredFont(forTextStyle: .title2), width: width) + 12

        if let photo = snapshot.correctedImage {
            let height = min(width * photo.size.height / max(photo.size.width, 1), 300)
            let photoWidth = height * photo.size.width / max(photo.size.height, 1)
            photo.draw(in: CGRect(x: margin, y: y, width: photoWidth, height: height))
            y += height + 16
        }

        for card in snapshot.sortedCards {
            let thumbnailHeight: CGFloat = 60
            if y + thumbnailHeight + 20 > pageSize.height - margin {
                context.beginPage()
                y = margin
            }
            let textX = margin + 110
            if let image = card.handwritingImage {
                let thumbnailWidth = min(100, thumbnailHeight * image.size.width / max(image.size.height, 1))
                image.draw(in: CGRect(x: margin, y: y, width: thumbnailWidth, height: thumbnailHeight))
            }
            let header = "\(card.timeRangeText)　\(card.category.label)　\(card.status.label)"
            var textY = y
            textY += draw(header, at: CGPoint(x: textX, y: textY), font: .preferredFont(forTextStyle: .headline), width: width - 110) + 2
            textY += draw(card.transcription, at: CGPoint(x: textX, y: textY), font: .preferredFont(forTextStyle: .body), width: width - 110)
            y = max(y + thumbnailHeight, textY) + 14
        }
    }

    /// 文字を描いて、使った高さを返す
    @discardableResult
    private static func draw(_ text: String, at point: CGPoint, font: UIFont, width: CGFloat) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        string.draw(with: CGRect(origin: point, size: CGSize(width: width, height: ceil(bounds.height))), options: [.usesLineFragmentOrigin], context: nil)
        return ceil(bounds.height)
    }
}
