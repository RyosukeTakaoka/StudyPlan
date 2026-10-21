import SwiftData
import SwiftUI

/// 01・今日（iPhone）：今 → 次 とワンタップ実績
struct TodayView: View {
    @Query(sort: \Snapshot.capturedAt, order: .reverse) private var snapshots: [Snapshot]
    @Environment(\.modelContext) private var modelContext
    @State private var showsCapture = false

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            if let snapshot = Snapshot.latest(on: now, in: snapshots), !snapshot.sortedCards.isEmpty {
                ScrollView {
                    TodayContent(snapshot: snapshot, now: now)
                }
                .background(Theme.screenBackground)
            } else {
                TodayEmptyState(
                    onCapture: { showsCapture = true },
                    onSample: { SampleData.insert(into: modelContext) }
                )
            }
        }
        .navigationTitle("今日")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsCapture = true } label: {
                    Label("撮影する", systemImage: "plus")
                }
            }
        }
        .fullScreenCover(isPresented: $showsCapture) {
            CaptureFlowView()
        }
    }
}

private struct TodayContent: View {
    let snapshot: Snapshot
    let now: Date

    var body: some View {
        let cards = snapshot.sortedCards
        let current = cards.first { $0.contains(now) }
        let next = cards.first { $0.start > now }

        VStack(alignment: .leading, spacing: 24) {
            header
            if let current {
                NowBlockSection(card: current, now: now)
            } else {
                Text("今のブロックはありません")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            if let next {
                NextBlockSection(card: next)
            }
            FlowSection(cards: cards, current: current)
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TimeText.fullDay(now))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack {
                    boardName
                    Spacer()
                    capturedAt
                }
                VStack(alignment: .leading, spacing: 4) {
                    boardName
                    capturedAt
                }
            }
        }
        .readableFloor()
    }

    private var boardName: some View {
        Label(snapshot.board?.name ?? "ボード", systemImage: "rectangle.on.rectangle")
            .font(TextRole.note)
            .foregroundStyle(.secondary)
    }

    private var capturedAt: some View {
        Text("撮影 \(TimeText.hm(snapshot.capturedAt))")
            .font(TextRole.note.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

/// 今のブロック
private struct NowBlockSection: View {
    let card: Card
    let now: Date
    @AppStorage(Preferences.flourishes) private var flourishes = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    label
                    Spacer()
                    remaining
                }
                VStack(alignment: .leading, spacing: 4) {
                    label
                    remaining
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        time
                        Spacer()
                        CategoryLabel(category: card.category)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        time
                        CategoryLabel(category: card.category)
                    }
                }
                CardStatusPanel(card: card, linksToDetail: true)
                TimeLogButton(card: card)
                    .font(TextRole.listRow)
            }
            .padding(14)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
    }

    /// 演出は1画面に1か所まで：実績を記録したら「今」の印は消す（完了なら線のほうが出る）
    private var showsMarker: Bool { flourishes && card.status == .planned }

    private var label: some View {
        Text("今のブロック")
            .font(.headline)
            .nowMarker(showsMarker)
    }

    private var remaining: some View {
        let minutes = max(0, Int(card.end.timeIntervalSince(now) / 60))
        return Text("あと\(minutes)分")
            .font(TextRole.note)
            .foregroundStyle(.secondary)
            .readableFloor()
    }

    private var time: some View {
        Text(card.timeRangeText)
            .font(.title3.weight(.semibold).monospacedDigit())
    }
}

/// 次のブロック
private struct NextBlockSection: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "次のブロック") {
                Text(TimeText.hm(card.start))
                    .font(TextRole.note.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            NavigationLink(value: card) {
                AdaptiveStack(spacing: 12) {
                    CardThumbnail(card: card, width: 110)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(card.timeRangeText)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                        CategoryLabel(category: card.category)
                        Text(card.title)
                            .font(TextRole.listRow)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// 今日の流れ（画像では小さかったので、文字の下限を決めてある）
private struct FlowSection: View {
    let cards: [Card]
    let current: Card?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "今日の流れ") {
                Text("全\(cards.count)件")
                    .font(TextRole.note)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(cards) { card in
                    NavigationLink(value: card) {
                        FlowRow(card: card, isCurrent: card.id == current?.id)
                    }
                    .buttonStyle(.plain)
                    if card.id != cards.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
        .readableFloor()
    }
}

private struct FlowRow: View {
    let card: Card
    let isCurrent: Bool

    var body: some View {
        AdaptiveStack(spacing: 10) {
            Text(TimeText.hm(card.start))
                .font(TextRole.listRow.monospacedDigit())
                .foregroundStyle(.secondary)
            CategoryLabel(category: card.category)
            Text(card.title)
                .font(TextRole.listRow)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isCurrent && card.status == .planned {
                NowTag()
            } else {
                StatusTag(status: card.status)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct TodayEmptyState: View {
    let onCapture: () -> Void
    let onSample: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("今日の写真はまだありません", systemImage: "camera.viewfinder")
        } description: {
            Text("ボードを撮影すると、行ごとのカードに切り出して「今」と「次」を表示します。")
        } actions: {
            Button("撮影する", action: onCapture)
                .buttonStyle(.borderedProminent)
            Button("サンプルで試す", action: onSample)
        }
    }
}

#Preview("今日・ライト") {
    NavigationStack { TodayView().cardDestinations() }
        .modelContainer(PreviewSupport.container)
}

#Preview("今日・ダーク・大きな文字") {
    NavigationStack { TodayView().cardDestinations() }
        .modelContainer(PreviewSupport.container)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility3)
}
