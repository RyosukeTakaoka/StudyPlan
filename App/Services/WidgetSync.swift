import Foundation
import SwiftData
import WidgetKit

/// 今日のカードを、ウィジェット用に App Group へ書き出す
enum WidgetSync {
    static func refresh(using context: ModelContext, now: Date = .now) {
        let descriptor = FetchDescriptor<Snapshot>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        let snapshots = (try? context.fetch(descriptor)) ?? []
        let cards = Snapshot.latest(on: now, in: snapshots)?.sortedCards ?? []

        var newImages: [String: Data] = [:]
        let blocks = cards.map { card -> WidgetBlock in
            let fileName = "\(card.id.uuidString).jpg"
            var hasImage = WidgetStore.imageExists(fileName)
            // 筆跡はカード全体を縮小せず、インクのある領域だけを切り出す
            if !hasImage, let image = card.handwritingImage,
               let data = InkCropper.croppedToInk(image).jpegData(compressionQuality: 0.8) {
                newImages[fileName] = data
                hasImage = true
            }
            return WidgetBlock(
                id: card.id,
                title: card.title,
                start: card.start,
                end: card.end,
                category: card.category,
                inkImageFile: hasImage ? fileName : nil
            )
        }
        WidgetStore.save(WidgetPayload(updatedAt: now, blocks: blocks), newImages: newImages)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.widgetKind)
    }
}
