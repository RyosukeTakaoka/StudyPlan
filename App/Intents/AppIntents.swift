import AppIntents
import Foundation
import SwiftData
import UIKit

// App Intents（v0.2）：ショートカットアプリや Siri、外部の AI から使う「アプリの口」。
// 返す JSON は DayPlanDTO（MCP サーバーと同じ形）。

// MARK: - 区分・状態の選択肢

enum CardStatusOption: String, AppEnum {
    case done, notDone = "not_done", carried, skipped, planned

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "状態"
    static var caseDisplayRepresentations: [CardStatusOption: DisplayRepresentation] = [
        .done: "完了", .notDone: "未完了", .carried: "持ち越し", .skipped: "スキップ", .planned: "予定に戻す"
    ]

    var status: CardStatus { CardStatus(rawValue: rawValue) ?? .planned }
}

// MARK: - カード

struct CardEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "カード"
    static var defaultQuery = CardEntityQuery()

    var id: UUID
    var title: String
    var timeRange: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(timeRange) \(title)")
    }

    init(card: Card) {
        id = card.id
        title = card.title
        timeRange = card.timeRangeText
    }
}

struct CardEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CardEntity] {
        let context = AppModelContainer.shared.mainContext
        let cards = ((try? context.fetch(FetchDescriptor<Card>())) ?? []).alive
        return cards.filter { identifiers.contains($0.id) }.map(CardEntity.init(card:))
    }

    /// 選択肢は今日のカード
    @MainActor
    func suggestedEntities() async throws -> [CardEntity] {
        IntentSupport.todayCards().map(CardEntity.init(card:))
    }
}

@MainActor
enum IntentSupport {
    static var context: ModelContext { AppModelContainer.shared.mainContext }

    static func todayCards(now: Date = .now) -> [Card] {
        let descriptor = FetchDescriptor<Snapshot>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        let snapshots = (try? context.fetch(descriptor)) ?? []
        return Snapshot.latest(on: now, in: snapshots)?.sortedCards ?? []
    }

    static func card(id: UUID) -> Card? {
        ((try? context.fetch(FetchDescriptor<Card>())) ?? []).alive.first { $0.id == id }
    }

    static func save() {
        try? context.save()
        WidgetSync.refresh(using: context)
    }
}

// MARK: - 読み取り

/// 指定日の計画と実績を JSON（DayPlanDTO）で返す
struct GetDayPlanIntent: AppIntent {
    static var title: LocalizedStringResource = "1日の計画と実績を取得"
    static var description = IntentDescription("指定した日のカード（時刻・文字起こし・状態・持ち越し回数）を JSON で返します。日付は日本時間です。")

    @Parameter(title: "日付")
    var date: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let dto = DayPlanExporter.dayPlan(for: date ?? .now, in: IntentSupport.context)
        return .result(value: dto.jsonString())
    }
}

/// 今と次のブロックを読み上げる
struct NowNextIntent: AppIntent {
    static var title: LocalizedStringResource = "今と次のブロック"
    static var description = IntentDescription("今のブロックと次のブロックを表示します。")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let cards = IntentSupport.todayCards(now: now)
        let current = cards.first { $0.contains(now) }
        let next = cards.first { $0.start > now }
        var lines: [String] = []
        lines.append(current.map { "今：\($0.title)（\($0.timeRangeText)）" } ?? "今のブロックはありません")
        if let next { lines.append("次：\(next.title)（\(TimeText.hm(next.start))から）") }
        return .result(dialog: IntentDialog(stringLiteral: lines.joined(separator: "\n")))
    }
}

// MARK: - 書き込み

/// カードの状態を記録する
struct RecordCardStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "カードの状態を記録"

    @Parameter(title: "カード")
    var card: CardEntity

    @Parameter(title: "状態")
    var status: CardStatusOption

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let target = IntentSupport.card(id: card.id) else {
            return .result(dialog: "カードが見つかりませんでした")
        }
        target.setStatus(status.status)
        IntentSupport.save()
        return .result(dialog: IntentDialog(stringLiteral: "\(target.title)を「\(target.status.label)」にしました"))
    }
}

/// 今のブロックを完了にする（アクションボタンなどに割り当てる用）
struct CompleteCurrentBlockIntent: AppIntent {
    static var title: LocalizedStringResource = "今のブロックを完了にする"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        guard let current = IntentSupport.todayCards(now: now).first(where: { $0.contains(now) }) else {
            return .result(dialog: "今のブロックはありません")
        }
        current.setStatus(.done)
        IntentSupport.save()
        return .result(dialog: IntentDialog(stringLiteral: "\(current.title)を完了にしました"))
    }
}

/// 実際の開始・終了を記録する
struct LogTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "実際の時間を記録"

    enum Action: String, AppEnum {
        case start, end
        static var typeDisplayRepresentation: TypeDisplayRepresentation = "記録"
        static var caseDisplayRepresentations: [Action: DisplayRepresentation] = [.start: "開始", .end: "終了"]
    }

    @Parameter(title: "カード")
    var card: CardEntity?

    @Parameter(title: "記録", default: .start)
    var action: Action

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let target = card.flatMap { IntentSupport.card(id: $0.id) }
            ?? IntentSupport.todayCards(now: now).first { $0.contains(now) }
        guard let target else { return .result(dialog: "対象のカードがありません") }
        switch action {
        case .start: target.startTimeLog(in: IntentSupport.context, at: now)
        case .end: target.endTimeLog(in: IntentSupport.context, at: now)
        }
        IntentSupport.save()
        return .result(dialog: IntentDialog(stringLiteral: "\(target.title)の\(action == .start ? "開始" : "終了")を記録しました"))
    }
}

/// 別ルート：AI が写真を読んで作った計画（DayPlanDTO の JSON）を取り込む。筆跡画像のないカードになる。
struct ImportDayPlanIntent: AppIntent {
    static var title: LocalizedStringResource = "計画をJSONから取り込む"
    static var description = IntentDescription("DayPlanDTO 形式の JSON から、その日のカードを作ります。筆跡画像はつきません。")

    @Parameter(title: "JSON", inputOptions: String.IntentInputOptions(multiline: true))
    var json: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let dto = try? DayPlanDTO.decoder.decode(DayPlanDTO.self, from: Data(json.utf8)),
              let day = TimeText.date(dayKey: dto.date) else {
            return .result(dialog: "JSON を読み取れませんでした。date と cards を含む DayPlanDTO の形で渡してください。")
        }
        // 時刻を読めなかったカードは除く。状態とずれないよう、カードと状態を組にしておく。
        let pairs = dto.cards.compactMap { item -> (draft: CardDraft, status: String)? in
            guard let start = TimeText.date(dayKey: dto.date, time: item.start) else { return nil }
            let end = TimeText.date(dayKey: dto.date, time: item.end) ?? start.addingTimeInterval(3600)
            let draft = CardDraft(
                image: nil, rect: .full, transcription: item.text, lines: [],
                start: start, end: max(end, start),
                category: BlockCategory(rawValue: item.category) ?? BlockCategory.guess(from: item.text)
            )
            return (draft, item.status)
        }
        let drafts = pairs.map { $0.draft }
        guard !drafts.isEmpty else { return .result(dialog: "取り込めるカードがありませんでした") }
        let context = IntentSupport.context
        let cards = SnapshotSaver.save(
            original: nil, corrected: UIImage(), didCorrect: false, day: day,
            drafts: drafts, board: Board.defaultBoard(in: context), context: context
        )
        // 状態も入っていれば反映する
        for (card, pair) in zip(cards, pairs) {
            if let status = CardStatus(rawValue: pair.status), status != .planned { card.setStatus(status) }
        }
        IntentSupport.save()
        return .result(dialog: IntentDialog(stringLiteral: "\(cards.count)件のカードを取り込みました"))
    }
}

// MARK: - ショートカット

struct StudyPlanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NowNextIntent(),
            phrases: ["\(.applicationName)で今と次を見る"],
            shortTitle: "今と次",
            systemImageName: "arrow.right.circle"
        )
        AppShortcut(
            intent: CompleteCurrentBlockIntent(),
            phrases: ["\(.applicationName)で今のブロックを完了"],
            shortTitle: "今を完了",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: GetDayPlanIntent(),
            phrases: ["\(.applicationName)で今日の計画を取得"],
            shortTitle: "計画をJSONで",
            systemImageName: "curlybraces"
        )
    }
}
