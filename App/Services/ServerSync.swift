import Foundation
import SwiftData

/// AI連携サーバー（Cloudflare Workers + D1）との同期。設定で明示的にオンにしたときだけ動く（初期値オフ）。
///
/// - 画像は送らない（has_handwriting_image で「あるかどうか」だけを伝える）
/// - 文字数などはサーバーの上限（server/src/sync.ts）に合わせて切り詰める
/// - POST /v1/sync/push：前回送ってから変わったものをまとめて送る。同じ内容を2回送っても結果は同じ（冪等）
/// - GET /v1/sync/pull?since=：サーバー側の変更（MCP のフェーズBでの書き込み）を受け取る。since には前回の cursor をそのまま渡す
/// - 競合したら updated_at が新しい方を採用する
/// - 送受信の形は server/src/sync.ts と同じ
/// - mainContext を使うので、メインスレッドで動かす（通信の待ち時間は画面を止めない）
@MainActor
enum ServerSync {
    // MARK: - 送受信の形

    struct Changes: Codable {
        var boards: [BoardRecord] = []
        var snapshots: [SnapshotRecord] = []
        var cards: [CardRecord] = []
        var timeLogs: [TimeLogRecord] = []

        var isEmpty: Bool { boards.isEmpty && snapshots.isEmpty && cards.isEmpty && timeLogs.isEmpty }
        var count: Int { boards.count + snapshots.count + cards.count + timeLogs.count }

        /// 1回に送る件数を maxRecords 件までに分ける（ボード → 写真 → カード → 時間ログの順）
        func chunked(maxRecords: Int) -> [Changes] {
            var chunks: [Changes] = []
            var current = Changes()
            func flushIfFull() {
                if current.count >= maxRecords {
                    chunks.append(current)
                    current = Changes()
                }
            }
            for record in boards { current.boards.append(record); flushIfFull() }
            for record in snapshots { current.snapshots.append(record); flushIfFull() }
            for record in cards { current.cards.append(record); flushIfFull() }
            for record in timeLogs { current.timeLogs.append(record); flushIfFull() }
            if !current.isEmpty { chunks.append(current) }
            return chunks
        }
    }

    struct BoardRecord: Codable {
        var id: String
        var updatedAt: String
        var deletedAt: String?
        var name: String
        var kind: String
    }

    struct SnapshotRecord: Codable {
        var id: String
        var updatedAt: String
        var deletedAt: String?
        var boardId: String?
        var targetDate: String
        var capturedAt: String
    }

    struct CardRecord: Codable {
        var id: String
        var updatedAt: String
        var deletedAt: String?
        var snapshotId: String?
        var date: String
        var text: String
        var start: String
        var end: String
        var category: String
        var status: String
        var carriedOverCount: Int
        var carriedFromCardId: String?
        var hasHandwritingImage: Bool
    }

    struct TimeLogRecord: Codable {
        var id: String
        var updatedAt: String
        var deletedAt: String?
        var cardId: String
        var actualStart: String
        var actualEnd: String?
    }

    struct PushRequest: Codable { var changes: Changes }
    struct PushResponse: Codable { var accepted: Int; var ignored: Int; var serverTime: String }
    struct PullResponse: Codable { var changes: Changes; var cursor: String; var hasMore: Bool? }

    /// 1回の push で送る件数（サーバーの上限 2000 より十分小さく）
    static let pushChunkSize = 500

    enum SyncError: LocalizedError {
        case notConfigured
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "サーバーのURLとAPIトークンを設定してください。"
            case .http(let code, let message): return "サーバーエラー（\(code)）：\(message)"
            }
        }
    }

    // MARK: - 日時の形

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// 小数秒のない形（2026-10-21T01:02:03Z）も読めるようにする
    private static let isoPlainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }
    static func date(fromISO string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoPlainFormatter.date(from: string)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - 同期

    /// 送ってから受け取る。結果を人が読める文で返す。
    static func syncNow(context: ModelContext) async throws -> String {
        let (baseURL, token) = try configuration()
        let defaults = UserDefaults.standard

        // 送る
        let pushStartedAt = Date()
        let lastPush = defaults.object(forKey: Preferences.lastPushAt) as? Date ?? .distantPast
        let changes = collectChanges(since: lastPush, context: context)
        var pushed = 0
        for chunk in changes.chunked(maxRecords: pushChunkSize) {
            let response: PushResponse = try await send(
                "POST", path: "/v1/sync/push", body: PushRequest(changes: chunk), baseURL: baseURL, token: token
            )
            pushed += response.accepted
        }
        // すべて送れたときだけ進める（途中で失敗したら、次回もう一度送る。同じ内容は冪等なので害はない）
        defaults.set(pushStartedAt, forKey: Preferences.lastPushAt)

        // 受け取る（多いときは has_more が false になるまで続ける）
        var cursor = defaults.string(forKey: Preferences.lastPullCursor) ?? ""
        var applied = 0
        for _ in 0..<100 {
            let pull: PullResponse = try await send(
                "GET", path: "/v1/sync/pull", query: [URLQueryItem(name: "since", value: cursor)],
                body: Optional<PushRequest>.none, baseURL: baseURL, token: token
            )
            applied += apply(pull.changes, context: context)
            try? context.save()
            cursor = pull.cursor
            defaults.set(cursor, forKey: Preferences.lastPullCursor)
            if pull.hasMore != true { break }
        }
        if applied > 0 { WidgetSync.refresh(using: context) }
        return "送信 \(pushed)件・反映 \(applied)件"
    }

    /// サーバー上の自分のデータをすべて消す（端末のデータは消さない）
    static func deleteAllServerData() async throws {
        let (baseURL, token) = try configuration()
        let _: [String: Bool] = try await send(
            "DELETE", path: "/v1/data", body: Optional<PushRequest>.none, baseURL: baseURL, token: token
        )
        UserDefaults.standard.removeObject(forKey: Preferences.lastPushAt)
        UserDefaults.standard.removeObject(forKey: Preferences.lastPullCursor)
    }

    private static func configuration() throws -> (URL, String) {
        guard let string = UserDefaults.standard.string(forKey: Preferences.serverURL),
              let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https" || url.host == "localhost" || url.host == "127.0.0.1",
              let token = Keychain.read(Keychain.serverTokenAccount), !token.isEmpty else {
            throw SyncError.notConfigured
        }
        return (url, token)
    }

    private static func send<Body: Encodable, Response: Decodable>(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Body?,
        baseURL: URL,
        token: String
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw SyncError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? ""
            throw SyncError.http(code, message)
        }
        return try decoder.decode(Response.self, from: data)
    }

    // MARK: - 端末 → サーバー

    static func collectChanges(since: Date, context: ModelContext) -> Changes {
        func fetch<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        var changes = Changes()
        changes.boards = fetch(Board.self).filter { $0.updatedAt > since }.map { board in
            BoardRecord(
                id: key(board.id), updatedAt: iso(board.updatedAt), deletedAt: board.deletedAt.map(iso),
                name: String(board.name.prefix(200)), kind: String(board.kindRaw.prefix(40))
            )
        }
        changes.snapshots = fetch(Snapshot.self).filter { $0.updatedAt > since && !$0.isSample && !$0.dayKey.isEmpty }.map { snapshot in
            SnapshotRecord(
                id: key(snapshot.id), updatedAt: iso(snapshot.updatedAt), deletedAt: snapshot.deletedAt.map(iso),
                boardId: snapshot.board.map { key($0.id) }, targetDate: snapshot.dayKey, capturedAt: iso(snapshot.capturedAt)
            )
        }
        changes.cards = fetch(Card.self).filter { $0.updatedAt > since && $0.snapshot?.isSample != true && !$0.dayKey.isEmpty }.map { card in
            CardRecord(
                id: key(card.id), updatedAt: iso(card.updatedAt), deletedAt: card.deletedAt.map(iso),
                snapshotId: card.snapshot.map { key($0.id) }, date: card.dayKey, text: String(card.transcription.prefix(4000)),
                start: TimeText.wireTime(card.start), end: TimeText.wireTime(card.end),
                category: String(card.categoryRaw.prefix(40)), status: card.status.rawValue, carriedOverCount: card.carriedOverCount,
                carriedFromCardId: card.carriedFromCardID.map(key), hasHandwritingImage: card.hasHandwritingImage
            )
        }
        changes.timeLogs = fetch(TimeLog.self).filter { $0.updatedAt > since && $0.card?.snapshot?.isSample != true }.compactMap { log in
            guard let card = log.card else { return nil }
            return TimeLogRecord(
                id: key(log.id), updatedAt: iso(log.updatedAt), deletedAt: log.deletedAt.map(iso),
                cardId: key(card.id), actualStart: TimeText.wireTime(log.actualStart),
                actualEnd: log.actualEnd.map(TimeText.wireTime)
            )
        }
        return changes
    }

    private static func key(_ id: UUID) -> String { id.uuidString.lowercased() }

    // MARK: - サーバー → 端末

    /// サーバーで変わったカードの状態と時間ログを反映する。新しい方を採用する。反映した件数を返す。
    static func apply(_ changes: Changes, context: ModelContext) -> Int {
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        var cardsByID: [String: Card] = [:]
        for card in cards { cardsByID[key(card.id)] = card }
        var applied = 0

        for record in changes.cards {
            guard let card = cardsByID[record.id], let remoteUpdated = date(fromISO: record.updatedAt),
                  remoteUpdated > card.updatedAt else { continue }
            card.statusRaw = CardStatus(rawValue: record.status)?.rawValue ?? card.statusRaw
            card.carriedOverCount = record.carriedOverCount
            card.deletedAt = record.deletedAt.flatMap(date(fromISO:))
            card.updatedAt = remoteUpdated
            applied += 1
        }

        let logs = (try? context.fetch(FetchDescriptor<TimeLog>())) ?? []
        var logsByID: [String: TimeLog] = [:]
        for log in logs { logsByID[key(log.id)] = log }
        for record in changes.timeLogs {
            guard let card = cardsByID[record.cardId], let remoteUpdated = date(fromISO: record.updatedAt),
                  let start = TimeText.date(dayKey: card.dayKey, time: record.actualStart) else { continue }
            let end = record.actualEnd.flatMap { TimeText.date(dayKey: card.dayKey, time: $0) }
            if let log = logsByID[record.id] {
                guard remoteUpdated > log.updatedAt else { continue }
                log.actualStart = start
                log.actualEnd = end
                log.deletedAt = record.deletedAt.flatMap(date(fromISO:))
                log.updatedAt = remoteUpdated
            } else if let id = UUID(uuidString: record.id) {
                let log = TimeLog(actualStart: start, actualEnd: end)
                log.id = id
                log.deletedAt = record.deletedAt.flatMap(date(fromISO:))
                context.insert(log)
                log.card = card
                log.updatedAt = remoteUpdated
            }
            applied += 1
        }
        return applied
    }
}
