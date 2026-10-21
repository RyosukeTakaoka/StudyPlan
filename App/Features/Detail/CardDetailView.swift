import SwiftData
import SwiftUI

/// 04・カード詳細：筆跡と状態。標準的な iOS の見た目を優先する。
/// 個性の演出は「完了の線」の1か所だけ。
struct CardDetailView: View {
    @State private var card: Card
    @State private var face: Face = .handwriting
    @State private var showsEditor = false
    @State private var completionToken = 0
    @Environment(\.modelContext) private var modelContext

    enum Face: String, CaseIterable, Identifiable {
        case handwriting = "筆跡"
        case transcription = "文字起こし"
        var id: Self { self }
    }

    init(card: Card) {
        _card = State(initialValue: card)
    }

    private var siblings: [Card] { card.snapshot?.sortedCards ?? [card] }
    private var index: Int { siblings.firstIndex { $0.id == card.id } ?? 0 }

    var body: some View {
        List {
            Section {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        CategoryLabel(category: card.category)
                        Spacer()
                        carriedText
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        CategoryLabel(category: card.category)
                        carriedText
                    }
                }
                Picker("表示", selection: $face) {
                    ForEach(Face.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch face {
                case .handwriting:
                    HandwritingImage(image: card.handwritingImage, fallbackText: card.transcription)
                        .completionStroke(isDone: card.status == .done, token: completionToken)
                        .accessibilityLabel("筆跡：\(card.transcription)")
                case .transcription:
                    Text(card.transcription.isEmpty ? "文字起こしはありません" : card.transcription)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section {
                LabeledContent("予定時刻", value: card.timeRangeText)
                LabeledContent("状態") {
                    Label(card.status.label, systemImage: card.status.symbol)
                }
                LabeledContent("持ち越し回数", value: "\(card.carriedOverCount)回")
                if let snapshot = card.snapshot {
                    LabeledContent("撮影", value: "\(TimeText.monthDay(snapshot.capturedAt)) \(TimeText.hm(snapshot.capturedAt))")
                }
            }

            Section("実績を記録") {
                StatusButtonsRow(selection: card.status) { tapped in
                    if card.toggle(tapped) == .done { completionToken += 1 }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            }

            Section {
                ForEach(card.aliveTimeLogs) { log in
                    LabeledContent("実際") {
                        Text(timeLogText(log)).monospacedDigit()
                    }
                }
                .onDelete { offsets in
                    let logs = card.aliveTimeLogs
                    for offset in offsets { logs[offset].softDelete() }
                    card.touch()
                }
                TimeLogButton(card: card)
            } header: {
                Text("時間ログ")
            } footer: {
                if let difference = differenceText {
                    Text(difference)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("カード詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsEditor = true
                } label: {
                    Label("直す", systemImage: "square.and.pencil")
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    move(by: -1)
                } label: {
                    Label("前へ", systemImage: "chevron.left")
                }
                .disabled(index == 0)
                Spacer()
                Text("\(index + 1) / \(siblings.count)")
                    .font(TextRole.note.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    move(by: 1)
                } label: {
                    Label("次へ", systemImage: "chevron.right")
                }
                .disabled(index >= siblings.count - 1)
            }
        }
        .sheet(isPresented: $showsEditor, onDismiss: {
            card.touch()
            WidgetSync.refresh(using: modelContext)
        }) {
            CardEditSheet(card: card)
        }
    }

    private var carriedText: some View {
        Text("持ち越し \(card.carriedOverCount)回")
            .font(TextRole.note)
            .foregroundStyle(.secondary)
    }

    private func move(by offset: Int) {
        let newIndex = index + offset
        guard siblings.indices.contains(newIndex) else { return }
        card = siblings[newIndex]
        completionToken = 0
    }

    private func timeLogText(_ log: TimeLog) -> String {
        let end = log.actualEnd.map(TimeText.hm) ?? "記録中"
        return "\(TimeText.hm(log.actualStart)) – \(end)"
    }

    /// 予定と実績の差（解釈はしない。数字だけ）
    private var differenceText: String? {
        guard let actualStart = card.actualStart, let actualEnd = card.actualEnd else { return nil }
        let planned = Int(card.end.timeIntervalSince(card.start) / 60)
        let actual = Int(actualEnd.timeIntervalSince(actualStart) / 60)
        return "予定 \(planned)分・実際 \(actual)分"
    }
}

/// 保存済みのカードを直す
private struct CardEditSheet: View {
    @Bindable var card: Card
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(card: Card) {
        self.card = card
        _start = State(initialValue: card.start)
        _end = State(initialValue: card.end)
    }

    var body: some View {
        NavigationStack {
            Form {
                CardFieldsForm(
                    start: $start,
                    end: $end,
                    category: $card.category,
                    transcription: $card.transcription
                )
            }
            .navigationTitle("カードを直す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        card.setTimes(start: start, end: end)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
