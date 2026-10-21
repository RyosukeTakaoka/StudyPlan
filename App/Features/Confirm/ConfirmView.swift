import SwiftUI

/// 03・確認：低信頼だけを直す。標準的な iOS の見た目を優先し、個性の演出は入れない。
/// iPad では左に元の写真、右にカードを並べ、選んだカードの位置を写真の上に示す。
struct ConfirmView: View {
    let capture: ProcessedCapture
    let onSave: ([CardDraft]) -> Void

    @State private var drafts: [CardDraft]
    @State private var selectedID: UUID?
    @State private var editing: DraftReference?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(capture: ProcessedCapture, onSave: @escaping ([CardDraft]) -> Void) {
        self.capture = capture
        self.onSave = onSave
        _drafts = State(initialValue: capture.drafts)
    }

    private struct DraftReference: Identifiable { let id: UUID }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("元の写真").font(.title2.bold())
                            photo
                            Text("選択中のカードの位置を、アクセント色の枠で示しています。")
                                .font(TextRole.note)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .frame(maxWidth: .infinity)
                    .background(Theme.screenBackground)
                    Divider()
                    cardList.frame(maxWidth: .infinity)
                }
            } else {
                cardList
            }
        }
        .navigationTitle("カードを確認")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) {
            Button {
                onSave(drafts)
            } label: {
                Text("\(drafts.count)件を保存").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(drafts.isEmpty)
            .padding()
            .background(.bar)
        }
        .sheet(item: $editing) { reference in
            if let index = drafts.firstIndex(where: { $0.id == reference.id }) {
                DraftEditSheet(draft: $drafts[index])
            }
        }
    }

    private var photo: some View {
        SnapshotPhotoView(
            image: capture.corrected,
            rects: drafts.map(\.rect),
            highlighted: drafts.firstIndex { $0.id == selectedID }
        )
    }

    private var reviewCount: Int { drafts.filter(\.needsReview).count }

    private var cardList: some View {
        List {
            if horizontalSizeClass != .regular {
                Section {
                    photo
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } footer: {
                    if !capture.didCorrect {
                        Text("ボードの枠を検出できなかったため、写真をそのまま使っています。")
                    }
                }
            }

            Section {
                ForEach(drafts) { draft in
                    Button {
                        selectedID = draft.id
                        editing = DraftReference(id: draft.id)
                    } label: {
                        DraftRow(draft: draft)
                    }
                    .listRowBackground(rowBackground(for: draft))
                }
                .onDelete { drafts.remove(atOffsets: $0) }

                Button {
                    addDraft()
                } label: {
                    Label("カードを追加", systemImage: "plus")
                }
            } header: {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("カード \(drafts.count)件")
                        Spacer()
                        reviewSummary
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("カード \(drafts.count)件")
                        reviewSummary
                    }
                }
            } footer: {
                Text("行をタップすると、時刻・区分・文字起こしを直せます。左にスワイプすると削除します。")
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var reviewSummary: some View {
        if reviewCount > 0 {
            Label("要確認 \(reviewCount)件", systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func rowBackground(for draft: CardDraft) -> Color? {
        if horizontalSizeClass == .regular && draft.id == selectedID { return Theme.accent.opacity(0.12) }
        if draft.needsReview { return Color(uiColor: .tertiarySystemFill) }
        return nil
    }

    private func addDraft() {
        let start = drafts.last?.end ?? capture.day
        let draft = CardDraft(
            image: capture.corrected,
            rect: .full,
            transcription: "",
            lines: [],
            start: start,
            end: start.addingTimeInterval(3600),
            category: .study,
            reviewReason: "時刻と内容を入れてください"
        )
        drafts.append(draft)
        selectedID = draft.id
        editing = DraftReference(id: draft.id)
    }
}

private struct DraftRow: View {
    let draft: CardDraft

    var body: some View {
        AdaptiveStack(spacing: 12) {
            HandwritingImage(image: draft.image, fallbackText: draft.title, cornerRadius: 6)
                .frame(width: 84)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                AdaptiveStack(spacing: 8) {
                    Text(TimeText.range(draft.start, draft.end))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    CategoryLabel(category: draft.category)
                }
                Text(draft.title)
                    .font(TextRole.listRow)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let reason = draft.reviewReason {
                    Label {
                        Text(reason)
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    }
                    .font(TextRole.note)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 2)
    }
}

/// 確認中のカードを直す
private struct DraftEditSheet: View {
    @Binding var draft: CardDraft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HandwritingImage(image: draft.image, fallbackText: draft.title)
                }
                CardFieldsForm(
                    start: $draft.start,
                    end: $draft.end,
                    category: $draft.category,
                    transcription: $draft.transcription
                )
            }
            .navigationTitle("カードを直す")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        draft.reviewReason = nil
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 時刻・区分・文字起こしの入力欄（確認画面とカード詳細で共通）
struct CardFieldsForm: View {
    @Binding var start: Date
    @Binding var end: Date
    @Binding var category: BlockCategory
    @Binding var transcription: String

    var body: some View {
        Section("時刻") {
            DatePicker("開始", selection: $start, displayedComponents: .hourAndMinute)
            DatePicker("終了", selection: $end, in: start..., displayedComponents: .hourAndMinute)
        }
        .onChange(of: start) { _, newStart in
            if end <= newStart { end = newStart.addingTimeInterval(30 * 60) }
        }
        Section("区分") {
            Picker("区分", selection: $category) {
                ForEach(BlockCategory.allCases) { category in
                    Label(category.label, systemImage: category.symbol).tag(category)
                }
            }
        }
        Section("文字起こし") {
            TextField("文字起こし", text: $transcription, axis: .vertical)
        }
    }
}
