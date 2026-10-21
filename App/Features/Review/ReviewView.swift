import SwiftData
import SwiftUI

/// 見返し（v0.3）：「先週の今日」を、答え（筆跡）を見る前に思い出してから開く。
/// 評価や助言はしない。
struct ReviewView: View {
    @Query(sort: \Snapshot.capturedAt, order: .reverse) private var snapshots: [Snapshot]
    @State private var revealed = false

    /// 6日以上前のうち、いちばん新しい日（ふつうは「先週の今日」）
    private var target: Snapshot? {
        let limit = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        return snapshots.alive.first { $0.targetDate <= limit }
    }

    var body: some View {
        Group {
            if let target {
                List {
                    Section {
                        Text(revealed ? "書いたものを見比べてみましょう。" : "答えを見る前に、この日に何を書いたか思い出してみましょう。")
                            .font(.body)
                    } header: {
                        Text(TimeText.fullDay(target.targetDate))
                    }

                    Section("カード \(target.sortedCards.count)件") {
                        ForEach(target.sortedCards) { card in
                            VStack(alignment: .leading, spacing: 8) {
                                AdaptiveStack(spacing: 8) {
                                    Text(card.timeRangeText).font(.subheadline.weight(.semibold).monospacedDigit())
                                    CategoryLabel(category: card.category)
                                }
                                if revealed {
                                    HandwritingImage(image: card.handwritingImage, fallbackText: card.transcription)
                                    StatusTag(status: card.status)
                                } else {
                                    Text("？")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, minHeight: 60)
                                        .background(Theme.imagePlaceholder, in: RoundedRectangle(cornerRadius: 10))
                                        .accessibilityLabel("まだ隠れています")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .safeAreaInset(edge: .bottom) {
                    if !revealed {
                        Button {
                            revealed = true
                        } label: {
                            Text("答えを見る").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .padding()
                        .background(.bar)
                    }
                }
            } else {
                ContentUnavailableView(
                    "見返す記録はまだありません",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("1週間ほど使うと、ここで「先週の今日」を見返せます。")
                )
            }
        }
        .navigationTitle("見返し")
        .navigationBarTitleDisplayMode(.inline)
    }
}
