import SwiftData
import SwiftUI

/// 筆跡画像。画像がないとき（文字だけで作ったカード）は文字起こしを代わりに出す。
struct HandwritingImage: View {
    let image: UIImage?
    var fallbackText: String = ""
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Theme.imagePlaceholder
                    .aspectRatio(2, contentMode: .fit)
                    .overlay {
                        Text(fallbackText.isEmpty ? "筆跡画像なし" : fallbackText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(8)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// 小さな筆跡画像（一覧用）。幅を固定し、高さは比率で決める。
struct CardThumbnail: View {
    let card: Card
    var width: CGFloat = 96

    var body: some View {
        HandwritingImage(image: card.handwritingImage, fallbackText: card.title, cornerRadius: 8)
            .frame(width: width)
            .accessibilityHidden(true)
    }
}

/// 文字が大きい（アクセシビリティサイズ）ときは、横並びを縦並びに切り替える
struct AdaptiveStack<Content: View>: View {
    var horizontalAlignment: HorizontalAlignment = .leading
    var verticalAlignment: VerticalAlignment = .center
    var spacing: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: horizontalAlignment, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: verticalAlignment, spacing: spacing))
        layout { content() }
    }
}

/// 見出し＋右側の補足。入りきらないとき（大きな文字）は縦に並べる。
struct SectionHeader<Trailing: View>: View {
    let title: String
    var font: Font = .headline
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                titleText
                Spacer()
                trailing()
            }
            VStack(alignment: .leading, spacing: 4) {
                titleText
                trailing()
            }
        }
    }

    private var titleText: some View {
        Text(title).font(font)
    }
}

/// 状態のタグ（予定のときは出さない）
struct StatusTag: View {
    let status: CardStatus

    var body: some View {
        if status != .planned {
            Label(status.label, systemImage: status.symbol)
                .font(TextRole.note)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// 実績を記録する4つのボタン（完了／未完了／持ち越し／スキップ）。
/// 選ばれているものは、アクセント色・太字・枠の太さの3つで示す（色だけに頼らない）。
/// 入りきらないときは 4列 → 2×2 → 縦1列 の順に切り替える。
struct StatusButtonsRow: View {
    let selection: CardStatus
    let onSelect: (CardStatus) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(CardStatus.recordable) { button($0, vertical: true) }
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    button(.done, vertical: true)
                    button(.notDone, vertical: true)
                }
                GridRow {
                    button(.carried, vertical: true)
                    button(.skipped, vertical: true)
                }
            }
            VStack(spacing: 8) {
                ForEach(CardStatus.recordable) { button($0, vertical: false) }
            }
        }
    }

    private func button(_ status: CardStatus, vertical: Bool) -> some View {
        let isSelected = selection == status
        return Button {
            onSelect(status)
        } label: {
            if vertical {
                VStack(spacing: 4) {
                    Image(systemName: status.symbol)
                    Text(status.label).lineLimit(1)
                }
            } else {
                Label(status.label, systemImage: status.symbol)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(StatusButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "もう一度押すと取り消します" : "")
    }
}

struct StatusButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .font(TextRole.listRow.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Theme.accent : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(shape.fill(isSelected ? Theme.accent.opacity(0.14) : Theme.cardBackground))
            .overlay(shape.strokeBorder(isSelected ? Theme.accent : Color(uiColor: .separator), lineWidth: isSelected ? 2 : 0.5))
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 筆跡画像＋実績ボタン。完了の線と触覚フィードバックはここでまとめて扱う。
struct CardStatusPanel: View {
    let card: Card
    var linksToDetail = false

    @State private var completionToken = 0

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if linksToDetail {
                    NavigationLink(value: card) { image }
                        .buttonStyle(.plain)
                } else {
                    image
                }
            }
            .completionStroke(isDone: card.status == .done, token: completionToken)

            StatusButtonsRow(selection: card.status) { tapped in
                if card.toggle(tapped) == .done { completionToken += 1 }
            }
        }
        .onChange(of: card.id) { _, _ in completionToken = 0 }
    }

    private var image: some View {
        HandwritingImage(image: card.handwritingImage, fallbackText: card.transcription)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("筆跡：\(card.transcription)")
            .accessibilityValue(card.status.label)
    }
}

/// 実際の時間を記録するボタン（開始／終了）
struct TimeLogButton: View {
    let card: Card
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if card.openTimeLog != nil {
            Button {
                card.endTimeLog(in: modelContext)
            } label: {
                Label("終了を記録", systemImage: "stop.circle")
            }
            .buttonStyle(.bordered)
        } else {
            Button {
                card.startTimeLog(in: modelContext)
            } label: {
                Label(card.aliveTimeLogs.isEmpty ? "開始を記録" : "もう一度開始", systemImage: "play.circle")
            }
            .buttonStyle(.bordered)
        }
    }
}

/// 元の写真の上に、カードの位置を枠で重ねる。選択中の枠はアクセント色で太くする。
struct SnapshotPhotoView: View {
    let image: UIImage?
    let rects: [NormalizedRect]
    var highlighted: Int?

    var body: some View {
        HandwritingImage(image: image, cornerRadius: 12)
            .overlay {
                GeometryReader { geometry in
                    ForEach(rects.indices, id: \.self) { index in
                        let rect = rects[index].cgRect(in: geometry.size)
                        let isHighlighted = index == highlighted
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                isHighlighted ? Theme.accent : Color.secondary.opacity(0.5),
                                style: StrokeStyle(lineWidth: isHighlighted ? 3 : 1, dash: isHighlighted ? [] : [4, 3])
                            )
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                .accessibilityHidden(true)
            }
    }
}

extension View {
    /// カードをタップしたときの行き先（カード詳細）
    func cardDestinations() -> some View {
        navigationDestination(for: Card.self) { CardDetailView(card: $0) }
    }
}
