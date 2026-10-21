import SwiftUI
import WidgetKit

@main
struct StudyPlanWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowNextWidget()
    }
}

/// ウィジェット「今→次」。ホーム画面（小・中）とロック画面（長方形）。
/// 筆跡はカード全体の縮小ではなく、インクのある領域を切り出した画像を使う。
/// 画像が小さすぎて読めないときのため、タイトルの文字起こしを必ず並べて出す。
struct NowNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.widgetKind, provider: NowNextProvider()) { entry in
            NowNextWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("今→次")
        .description("今のブロックと次のブロックを、自分の筆跡で表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct NowNextEntry: TimelineEntry {
    let date: Date
    let now: WidgetBlock?
    let next: WidgetBlock?

    static let placeholder: NowNextEntry = {
        let start = Date()
        return NowNextEntry(
            date: start,
            now: WidgetBlock(id: UUID(), title: "鑑定理論", start: start, end: start.addingTimeInterval(5400), category: .study, inkImageFile: nil),
            next: WidgetBlock(id: UUID(), title: "過去問", start: start.addingTimeInterval(6300), end: start.addingTimeInterval(9000), category: .study, inkImageFile: nil)
        )
    }()
}

/// ブロックの開始・終了の時刻ごとに表示を切り替える。時刻ごとの表示をあらかじめ登録するので、サーバーは不要。
struct NowNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowNextEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NowNextEntry) -> Void) {
        let blocks = loadBlocks()
        completion(context.isPreview && blocks.isEmpty ? .placeholder : entry(at: .now, blocks: blocks))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowNextEntry>) -> Void) {
        let now = Date()
        let blocks = loadBlocks()
        let changes = blocks.flatMap { [$0.start, $0.end] }.filter { $0 > now }
        let dates = [now] + Array(Set(changes)).sorted()
        let entries = dates.map { entry(at: $0, blocks: blocks) }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(tomorrow)))
    }

    private func loadBlocks() -> [WidgetBlock] {
        (WidgetStore.load()?.blocks ?? []).sorted { $0.start < $1.start }
    }

    private func entry(at date: Date, blocks: [WidgetBlock]) -> NowNextEntry {
        NowNextEntry(
            date: date,
            now: blocks.first { $0.start <= date && date < $0.end },
            next: blocks.first { $0.start > date }
        )
    }
}

struct NowNextWidgetView: View {
    let entry: NowNextEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            HStack(alignment: .top, spacing: 12) {
                BlockColumn(label: "今", block: entry.now)
                Divider()
                BlockColumn(label: "次", block: entry.next)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                LockScreenRow(label: "今", block: entry.now)
                LockScreenRow(label: "次", block: entry.next)
            }
        default:
            if let block = entry.now ?? entry.next {
                BlockColumn(label: entry.now != nil ? "今" : "次", block: block)
            } else {
                EmptyMessage()
            }
        }
    }
}

/// ホーム画面：ラベル・筆跡・タイトル（文字起こし）
private struct BlockColumn: View {
    let label: String
    let block: WidgetBlock?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let block {
                Text("\(label) · \(TimeText.hm(block.start))")
                    .font(TextRole.note.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                InkImage(block: block)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                BlockTitle(block: block)
            } else {
                Text(label)
                    .font(TextRole.note.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text("予定はありません")
                    .font(TextRole.note)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// ロック画面：小さな筆跡＋「今 タイトル」＋時刻
private struct LockScreenRow: View {
    let label: String
    let block: WidgetBlock?

    var body: some View {
        HStack(spacing: 6) {
            if let block {
                InkImage(block: block)
                    .frame(width: 34, height: 20)
                Text("\(label) \(block.title)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(TimeText.hm(block.start))
                    .font(.footnote.monospacedDigit())
            } else {
                Text("\(label) なし")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BlockTitle: View {
    let block: WidgetBlock

    var body: some View {
        Label {
            Text(block.title)
                .lineLimit(2)
        } icon: {
            Image(systemName: block.category.symbol)
                .foregroundStyle(block.category.color)
        }
        .font(.subheadline.weight(.semibold))
        .accessibilityLabel("\(block.category.label)：\(block.title)")
    }
}

private struct InkImage: View {
    let block: WidgetBlock

    var body: some View {
        if let file = block.inkImageFile, let image = WidgetStore.inkImage(named: file) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

private struct EmptyMessage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日の写真はまだありません")
                .font(.subheadline.weight(.semibold))
            Text("アプリでボードを撮影してください")
                .font(TextRole.note)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
