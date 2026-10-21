import SwiftData
import SwiftUI

/// 05・比較：同じボードの別の日を、同じ大きさで並べる。差分の解釈や評価はしない（見せるだけ）。
struct CompareView: View {
    @Query(sort: \Snapshot.capturedAt, order: .reverse) private var allSnapshots: [Snapshot]
    @State private var comparedID: UUID?
    @State private var slot: String?

    /// 1日1枚（その日の最新）
    private var snapshots: [Snapshot] {
        var seen = Set<String>()
        return allSnapshots.alive.filter { seen.insert($0.dayKey).inserted }
    }

    var body: some View {
        let days = snapshots
        Group {
            if let base = days.first, days.count > 1 {
                let others = Array(days.dropFirst())
                let compared = others.first { $0.id == comparedID } ?? others[0]
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(base.board?.name ?? "同じボード")
                            .font(TextRole.note)
                            .foregroundStyle(.secondary)
                        dateChips(base: base, others: others, selected: compared)
                        pair(base: base, compared: compared, others: others)
                        Text("日付を左右にスワイプして切り替えられます")
                            .font(TextRole.note)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        sameBlock(base: base, compared: compared)
                        Text("解釈や評価は表示しません")
                            .font(TextRole.note)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .readableFloor()
                }
                .background(Theme.screenBackground)
            } else {
                ContentUnavailableView(
                    "比べる写真がまだありません",
                    systemImage: "square.split.2x1",
                    description: Text("2日分以上撮影すると、同じボードを並べて見られます。")
                )
            }
        }
        .navigationTitle("並べて見る")
    }

    private func relativeLabel(_ snapshot: Snapshot, from base: Snapshot) -> String {
        let days = Calendar.current.dateComponents([.day], from: snapshot.targetDate, to: base.targetDate).day ?? 0
        let prefix: String
        switch days {
        case 0: prefix = "同じ日"
        case 1: prefix = "昨日"
        case 7: prefix = "先週"
        default: prefix = "\(days)日前"
        }
        return "\(prefix)・\(TimeText.monthDay(snapshot.targetDate))"
    }

    private func dateChips(base: Snapshot, others: [Snapshot], selected: Snapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(others) { snapshot in
                    let isSelected = snapshot.id == selected.id
                    Button {
                        comparedID = snapshot.id
                    } label: {
                        Label(relativeLabel(snapshot, from: base), systemImage: isSelected ? "checkmark" : "calendar")
                            .font(TextRole.note.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Theme.accent : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? Theme.accent.opacity(0.14) : Theme.cardBackground, in: Capsule())
                            .overlay(Capsule().strokeBorder(isSelected ? Theme.accent : Color(uiColor: .separator), lineWidth: isSelected ? 1.5 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func pair(base: Snapshot, compared: Snapshot, others: [Snapshot]) -> some View {
        AdaptiveStack(verticalAlignment: .top, spacing: 12) {
            photoColumn(base, label: "今回・\(TimeText.monthDay(base.targetDate))")
            photoColumn(compared, label: relativeLabel(compared, from: base))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard let index = others.firstIndex(where: { $0.id == compared.id }) else { return }
                if value.translation.width < -50, index + 1 < others.count {
                    comparedID = others[index + 1].id
                } else if value.translation.width > 50, index > 0 {
                    comparedID = others[index - 1].id
                }
            }
        )
    }

    private func photoColumn(_ snapshot: Snapshot, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(TextRole.note)
                .foregroundStyle(.secondary)
            // 同じ大きさで見比べるため、枠の比率をそろえる
            Theme.imagePlaceholder
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    if let image = snapshot.correctedImage {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("\(label)の写真")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func sameBlock(base: Snapshot, compared: Snapshot) -> some View {
        let baseCards = base.sortedCards
        let slots = baseCards.map { TimeText.hm($0.start) }
        let current = slot.flatMap { slots.contains($0) ? $0 : nil } ?? slots.first
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "同じブロック") {
                if !slots.isEmpty {
                    Picker("時刻", selection: Binding(get: { current ?? "" }, set: { slot = $0 })) {
                        ForEach(baseCards) { card in
                            Text("\(TimeText.hm(card.start)) \(card.title)").tag(TimeText.hm(card.start))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            if let current {
                blockRow(label: "今回", card: baseCards.first { TimeText.hm($0.start) == current })
                blockRow(label: relativeLabel(compared, from: base), card: compared.sortedCards.first { TimeText.hm($0.start) == current })
            }
        }
    }

    private func blockRow(label: String, card: Card?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(TextRole.note)
                .foregroundStyle(.secondary)
            if let card {
                NavigationLink(value: card) {
                    HandwritingImage(image: card.handwritingImage, fallbackText: card.title)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            } else {
                Text("この時刻のカードはありません")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
