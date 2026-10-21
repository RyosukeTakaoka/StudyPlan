import SwiftData
import SwiftUI

/// 06・検索：端末内の文字起こしを検索し、ヒットした場所を筆跡画像の上に重ねる
struct SearchView: View {
    @Query(sort: \Card.start, order: .reverse) private var cards: [Card]
    @State private var query = ""

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = trimmed.isEmpty ? [] : cards.alive.filter { $0.transcription.localizedStandardContains(trimmed) }

        List {
            if trimmed.isEmpty {
                Text("筆跡の文字起こしから探します。写真と文字認識は端末内だけで扱います。")
                    .font(TextRole.note)
                    .foregroundStyle(.secondary)
            } else if results.isEmpty {
                ContentUnavailableView.search(text: trimmed)
            } else {
                Section {
                    ForEach(results) { card in
                        NavigationLink(value: card) {
                            SearchResultRow(card: card, query: trimmed)
                        }
                    }
                } header: {
                    Text("\(results.count)件・画像の上に一致した箇所を表示")
                }
            }
        }
        .listStyle(.insetGrouped)
        .readableFloor()
        .searchable(text: $query, prompt: "例：民法")
        .navigationTitle("検索")
    }
}

private struct SearchResultRow: View {
    let card: Card
    let query: String

    var body: some View {
        let matches = card.lines.filter { $0.text.localizedStandardContains(query) }
        AdaptiveStack(spacing: 12) {
            HandwritingImage(image: card.handwritingImage, fallbackText: card.title, cornerRadius: 8)
                .frame(width: 110)
                .overlay {
                    GeometryReader { geometry in
                        ForEach(matches.indices, id: \.self) { index in
                            let rect = matches[index].rect.cgRect(in: geometry.size).insetBy(dx: -3, dy: -2)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.accent.opacity(0.15))
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.accent, lineWidth: 2))
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title).font(.headline)
                Text("\(TimeText.monthDay(card.start)) \(TimeText.hm(card.start))")
                    .font(TextRole.note.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let line = matches.first?.text ?? card.transcription.split(whereSeparator: \.isNewline).first.map(String.init) {
                    Text("「\(line)」")
                        .font(TextRole.listRow)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}
