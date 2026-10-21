import SwiftData
import SwiftUI

/// iPad・今日：左に元の写真、右にカード。選んだカードの位置を写真の上に枠で示す。
struct IPadTodayView: View {
    @Query(sort: \Snapshot.capturedAt, order: .reverse) private var snapshots: [Snapshot]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedCardID: UUID?
    @State private var showsCapture = false

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            if let snapshot = Snapshot.latest(on: now, in: snapshots), !snapshot.sortedCards.isEmpty {
                content(snapshot: snapshot, now: now)
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

    @ViewBuilder
    private func content(snapshot: Snapshot, now: Date) -> some View {
        let cards = snapshot.sortedCards
        let current = cards.first { $0.contains(now) }
        let selected = cards.first { $0.id == selectedCardID } ?? current ?? cards[0]
        let selectedIndex = cards.firstIndex { $0.id == selected.id }

        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(TimeText.fullDay(now))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SectionHeader(title: "元の写真", font: .title2.bold()) {
                        if snapshot.didCorrectPerspective {
                            Label("補正済み", systemImage: "perspective")
                                .font(TextRole.note)
                                .foregroundStyle(.secondary)
                        }
                    }
                    SnapshotPhotoView(image: snapshot.correctedImage, rects: cards.map(\.crop), highlighted: selectedIndex)
                    Text("選択中のカードの位置を、アクセント色の枠で示しています。")
                        .font(TextRole.note)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .readableFloor()
            }
            .frame(maxWidth: .infinity)
            .background(Theme.screenBackground)

            Divider()

            VStack(spacing: 0) {
                List(selection: Binding<UUID?>(get: { selected.id }, set: { selectedCardID = $0 })) {
                    Section {
                        ForEach(cards) { card in
                            IPadCardRow(
                                card: card,
                                isCurrent: card.id == current?.id,
                                // 演出は1画面に1か所まで：下の欄で完了の線が出ているときは「今」の印を出さない
                                showsMarker: selected.status != .done
                            )
                            .tag(card.id)
                        }
                    } header: {
                        Text("カード \(cards.count)件")
                    }
                }
                .listStyle(.insetGrouped)

                SelectedCardPanel(card: selected)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct IPadCardRow: View {
    let card: Card
    let isCurrent: Bool
    let showsMarker: Bool
    @AppStorage(Preferences.flourishes) private var flourishes = true

    var body: some View {
        AdaptiveStack(spacing: 12) {
            CardThumbnail(card: card, width: 120)
            VStack(alignment: .leading, spacing: 4) {
                AdaptiveStack(spacing: 8) {
                    Text(card.timeRangeText)
                        .font(.headline.monospacedDigit())
                    if isCurrent && card.status == .planned {
                        NowTag(showsMarker: flourishes && showsMarker)
                    }
                }
                CategoryLabel(category: card.category)
                Text(card.title)
                    .font(TextRole.listRow)
                    .foregroundStyle(.secondary)
                StatusTag(status: card.status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// 選んだカードの実績を記録する欄
private struct SelectedCardPanel: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveStack(spacing: 8) {
                Text(card.timeRangeText).font(.headline.monospacedDigit())
                Text(card.title).font(TextRole.listRow).foregroundStyle(.secondary)
            }
            AdaptiveStack(verticalAlignment: .top, spacing: 12) {
                CardStatusPanel(card: card, linksToDetail: true)
                    .frame(maxWidth: 520)
                TimeLogButton(card: card)
            }
        }
        .padding()
        .background(.bar)
    }
}
