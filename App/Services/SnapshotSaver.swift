import Foundation
import SwiftData
import UIKit

/// 確認済みのカードを保存する
enum SnapshotSaver {
    @discardableResult
    static func save(
        original: UIImage?,
        corrected: UIImage,
        didCorrect: Bool,
        day: Date,
        capturedAt: Date = .now,
        drafts: [CardDraft],
        board: Board,
        isSample: Bool = false,
        context: ModelContext
    ) -> [Card] {
        let snapshot = Snapshot(capturedAt: capturedAt, targetDate: day)
        snapshot.originalPhoto = original?.downscaled(maxDimension: 2400).jpegData(compressionQuality: 0.8)
        snapshot.correctedPhoto = corrected.downscaled(maxDimension: 2400).jpegData(compressionQuality: 0.85)
        snapshot.didCorrectPerspective = didCorrect
        snapshot.fullText = drafts.map(\.transcription).joined(separator: "\n")
        snapshot.isSample = isSample
        context.insert(snapshot)
        snapshot.board = board

        let carriedCandidates = recentCarriedCards(before: Calendar.current.startOfDay(for: day), context: context)
        var cards: [Card] = []
        for draft in drafts {
            let card = Card(
                handwriting: draft.image?.downscaled(maxDimension: 1200).jpegData(compressionQuality: 0.85),
                crop: draft.rect,
                transcription: draft.transcription,
                lines: draft.lines,
                start: draft.start,
                end: draft.end,
                category: draft.category
            )
            // 日付をまたぐカードも、撮影した日（写真の対象日）のカードとして扱う
            card.dayKey = snapshot.dayKey
            context.insert(card)
            snapshot.cards?.append(card)
            // 前に持ち越したカードと同じタイトルなら、持ち越し元としてつなぎ、回数を引き継ぐ
            if let origin = carriedCandidates.first(where: { $0.title == card.title }) {
                card.carriedFromCardID = origin.id
                card.carriedOverCount = origin.carriedOverCount
            }
            cards.append(card)
        }

        // 次回の定点撮影で重ねる写真。画像のない取り込み（App Intents）とサンプルでは前回のものを残す。
        let reference = original ?? corrected
        if !isSample, let data = reference.downscaled(maxDimension: 1600).jpegData(compressionQuality: 0.7) {
            board.referencePhoto = data
            board.touch()
        }
        try? context.save()
        return cards
    }

    /// 直近7日の「持ち越し」のカード（新しい順）
    private static func recentCarriedCards(before day: Date, context: ModelContext) -> [Card] {
        let since = day.addingTimeInterval(-7 * 86_400)
        let carried = CardStatus.carried.rawValue
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate { $0.statusRaw == carried && $0.start >= since && $0.start < day },
            sortBy: [SortDescriptor(\.start, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).alive
    }
}
