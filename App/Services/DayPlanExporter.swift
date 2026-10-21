import Foundation
import SwiftData

/// カードを DayPlanDTO（AI に渡す形）に変換する
enum DayPlanExporter {
    static func dto(dayKey: String, cards: [Card]) -> DayPlanDTO {
        DayPlanDTO(
            date: dayKey,
            cards: cards.alive.sorted { $0.start < $1.start }.map(dto(for:))
        )
    }

    static func dto(for card: Card) -> DayPlanDTO.Card {
        DayPlanDTO.Card(
            id: card.id.uuidString.lowercased(),
            text: card.transcription,
            start: TimeText.wireTime(card.start),
            end: TimeText.wireTime(card.end),
            category: card.category.rawValue,
            status: card.status.rawValue,
            actualStart: card.actualStart.map(TimeText.wireTime),
            actualEnd: card.actualEnd.map(TimeText.wireTime),
            carriedOverCount: card.carriedOverCount,
            hasHandwritingImage: card.hasHandwritingImage
        )
    }

    /// 指定日の計画と実績（その日の最新の写真のカード）
    static func dayPlan(for day: Date, in context: ModelContext) -> DayPlanDTO {
        let descriptor = FetchDescriptor<Snapshot>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        let snapshots = (try? context.fetch(descriptor)) ?? []
        let cards = Snapshot.latest(on: day, in: snapshots)?.sortedCards ?? []
        return dto(dayKey: TimeText.dayKey(day), cards: cards)
    }
}
