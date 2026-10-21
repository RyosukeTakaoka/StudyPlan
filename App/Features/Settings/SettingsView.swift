import SwiftData
import SwiftUI

/// 設定。標準的な iOS の見た目（Form）を優先する。
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Board.createdAt) private var boards: [Board]

    @AppStorage(Preferences.flourishes) private var flourishes = true
    @AppStorage(Preferences.iCloudSync) private var iCloudSync = false
    @AppStorage(Preferences.reviewReminder) private var reviewReminder = false
    @AppStorage(Preferences.reviewWeekday) private var reviewWeekday = 1
    @AppStorage(Preferences.reviewHour) private var reviewHour = 20
    @AppStorage(Preferences.serverSync) private var serverSync = false
    @AppStorage(Preferences.serverURL) private var serverURL = ""

    @State private var exportRange: PDFExporter.Range = .week
    @State private var exportedPDF: URL?
    @State private var token = Keychain.read(Keychain.serverTokenAccount) ?? ""
    @State private var syncMessage: String?
    @State private var isSyncing = false
    @State private var confirmsServerDeletion = false
    @State private var copiedJSON = false

    var body: some View {
        Form {
            Section {
                Toggle("完了の線と「今」の印", isOn: $flourishes)
            } header: {
                Text("表示")
            } footer: {
                Text("オフにすると演出をすべて外します。状態はアイコンと文字で表示されるので、使い方は変わりません。")
            }

            if let board = boards.alive.first {
                Section("ボード") {
                    TextField("ボードの名前", text: Bindable(board).name)
                        .onSubmit { board.touch() }
                    LabeledContent("種類", value: board.kind.label)
                }
            }

            reviewSection
            exportSection
            iCloudSection
            serverSection

            Section {
                Button("サンプルデータを入れる") {
                    SampleData.insert(into: modelContext)
                }
            } header: {
                Text("動作確認")
            } footer: {
                Text("合成した筆跡画像で、今日・昨日・先週の記録を作ります。もう一度押すと作り直します。サンプルはサーバーには送りません。")
            }

            Section("このアプリについて") {
                LabeledContent("写真と文字認識", value: "端末内で処理")
                LabeledContent("バージョン", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
            }
        }
        .navigationTitle("設定")
        .readableFloor()
    }

    // MARK: - 見返し

    private var reviewSection: some View {
        Section {
            Toggle("見返しのきっかけ通知", isOn: $reviewReminder)
            if reviewReminder {
                Picker("曜日", selection: $reviewWeekday) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(Calendar.current.weekdaySymbols[weekday - 1]).tag(weekday)
                    }
                }
                Picker("時刻", selection: $reviewHour) {
                    ForEach(6...23, id: \.self) { hour in
                        Text("\(hour):00").tag(hour)
                    }
                }
            }
            NavigationLink("今すぐ見返す") { ReviewView() }
        } header: {
            Text("見返し")
        } footer: {
            Text("週に1回だけ、音を鳴らさずに「先週の今日」をお知らせします。")
        }
        .onChange(of: reviewReminder) { _, _ in updateReminder() }
        .onChange(of: reviewWeekday) { _, _ in updateReminder() }
        .onChange(of: reviewHour) { _, _ in updateReminder() }
    }

    private func updateReminder() {
        guard reviewReminder else {
            ReviewReminder.cancel()
            return
        }
        Task {
            let granted = await ReviewReminder.schedule(weekday: reviewWeekday, hour: reviewHour)
            if !granted { reviewReminder = false }
        }
    }

    // MARK: - 書き出し

    private var exportSection: some View {
        Section {
            Picker("期間", selection: $exportRange) {
                ForEach(PDFExporter.Range.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: exportRange) { _, _ in exportedPDF = nil }
            if let exportedPDF {
                ShareLink(item: exportedPDF) {
                    Label("PDFを共有", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    exportedPDF = try? PDFExporter.export(range: exportRange, endingOn: .now, context: modelContext)
                } label: {
                    Label("検索できるPDFを作る", systemImage: "doc.richtext")
                }
            }
            Button {
                UIPasteboard.general.string = DayPlanExporter.dayPlan(for: .now, in: modelContext).jsonString()
                copiedJSON = true
            } label: {
                Label(copiedJSON ? "コピーしました" : "今日の計画と実績をJSONでコピー", systemImage: "doc.on.clipboard")
            }
        } header: {
            Text("書き出し")
        } footer: {
            Text("JSONはAIにそのまま渡せる形（DayPlanDTO）です。ショートカットアプリからも取り出せます。")
        }
    }

    // MARK: - iCloud

    private var iCloudSection: some View {
        Section {
            Toggle("iCloudで端末間を同期", isOn: $iCloudSync)
        } header: {
            Text("iCloud同期")
        } footer: {
            if iCloudSync != AppModelContainer.isCloudKitEnabled {
                Text("アプリを終了して開き直すと切り替わります。")
            } else {
                Text("iPhoneとiPadで同じ記録を見るときに使います。初期値はオフで、オフのあいだは端末の中だけに保存します。")
            }
        }
    }

    // MARK: - AI連携サーバー

    private var serverSection: some View {
        Section {
            Toggle("AI連携サーバーと同期", isOn: $serverSync)
            if serverSync {
                TextField("サーバーのURL（https://…）", text: $serverURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("APIトークン", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: token) { _, newValue in
                        Keychain.save(newValue, for: Keychain.serverTokenAccount)
                    }
                Button {
                    isSyncing = true
                    Task {
                        do {
                            syncMessage = try await ServerSync.syncNow(context: modelContext)
                        } catch {
                            syncMessage = error.localizedDescription
                        }
                        isSyncing = false
                    }
                } label: {
                    HStack {
                        Label("今すぐ同期", systemImage: "arrow.triangle.2.circlepath")
                        if isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(isSyncing)
                if let syncMessage {
                    Text(syncMessage)
                        .font(TextRole.note)
                        .foregroundStyle(.secondary)
                }
                Button("サーバー上の自分のデータをすべて削除", role: .destructive) {
                    confirmsServerDeletion = true
                }
                .confirmationDialog("サーバー上のデータを削除しますか？", isPresented: $confirmsServerDeletion, titleVisibility: .visible) {
                    Button("削除する", role: .destructive) {
                        Task {
                            do {
                                try await ServerSync.deleteAllServerData()
                                syncMessage = "サーバー上のデータを削除しました。"
                            } catch {
                                syncMessage = error.localizedDescription
                            }
                        }
                    }
                } message: {
                    Text("この端末のデータは消えません。")
                }
            }
        } header: {
            Text("AI連携サーバー")
        } footer: {
            Text("計画と実績（文字起こし・時刻・状態）だけを送ります。写真と筆跡画像は送りません。初期値はオフです。")
        }
    }
}
