import SwiftData
import SwiftUI

@main
struct StudyPlanApp: App {
    @ObservedObject private var notificationRouter = NotificationRouter.shared

    init() {
        // 通知の受け取り先は、起動が終わる前に決めておく
        _ = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(notificationRouter)
        }
        .modelContainer(AppModelContainer.shared)
    }
}

enum AppSection: String, Hashable, CaseIterable, Identifiable {
    case today, records, search, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .today: return "今日"
        case .records: return "記録"
        case .search: return "検索"
        case .settings: return "設定"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "house"
        case .records: return "square.split.2x1"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}

/// iPhone はタブ、iPad は NavigationSplitView（左に一覧、右に中身）
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var notificationRouter: NotificationRouter
    @AppStorage(Preferences.serverSync) private var serverSync = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                SplitRootView()
            } else {
                PhoneRootView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            WidgetSync.refresh(using: modelContext)
            if serverSync {
                Task { _ = try? await ServerSync.syncNow(context: modelContext) }
            }
        }
        .sheet(isPresented: $notificationRouter.showsReview) {
            NavigationStack {
                ReviewView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { notificationRouter.showsReview = false }
                        }
                    }
            }
        }
    }
}

private struct PhoneRootView: View {
    @State private var selection: AppSection = .today

    var body: some View {
        TabView(selection: $selection) {
            ForEach(AppSection.allCases) { section in
                NavigationStack {
                    root(for: section).cardDestinations()
                }
                .tabItem { Label(section.title, systemImage: section.symbol) }
                .tag(section)
            }
        }
    }

    @ViewBuilder
    private func root(for section: AppSection) -> some View {
        switch section {
        case .today: TodayView()
        case .records: CompareView()
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }
}

private struct SplitRootView: View {
    @State private var selection: AppSection? = .today
    @Query(sort: \Board.createdAt) private var boards: [Board]

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach([AppSection.today, .records, .search]) { section in
                        Label(section.title, systemImage: section.symbol).tag(section)
                    }
                }
                Section("アプリ") {
                    Label(AppSection.settings.title, systemImage: AppSection.settings.symbol)
                        .tag(AppSection.settings)
                }
                if let board = boards.alive.first {
                    Section("今日のボード") {
                        Label(board.name, systemImage: "rectangle.on.rectangle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("手書きの記録")
        } detail: {
            NavigationStack {
                detail.cardDestinations()
            }
            .id(selection)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .today {
        case .today: IPadTodayView()
        case .records: CompareView()
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }
}
