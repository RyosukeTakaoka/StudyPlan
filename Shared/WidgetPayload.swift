import Foundation
import UIKit

/// ウィジェットに渡す1ブロック分の情報
struct WidgetBlock: Codable, Hashable, Identifiable {
    var id: UUID
    /// 文字起こしのタイトル。筆跡画像が小さくて読めないときのため、必ず画像と並べて出す。
    var title: String
    var start: Date
    var end: Date
    var category: BlockCategory
    /// インクのある領域だけを切り出した画像のファイル名（App Group 内）
    var inkImageFile: String?
}

struct WidgetPayload: Codable {
    var updatedAt: Date
    var blocks: [WidgetBlock]
}

/// アプリとウィジェットでデータを共有する場所（App Group）
enum WidgetStore {
    static let appGroupID = "group.com.ryosuketakaoka.studyplan"
    static let widgetKind = "NowNext"

    private static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Widget", isDirectory: true)
    }

    static func load() -> WidgetPayload? {
        guard let url = directory?.appendingPathComponent("payload.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetPayload.self, from: data)
    }

    static func imageExists(_ fileName: String) -> Bool {
        guard let url = directory?.appendingPathComponent(fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func inkImage(named fileName: String) -> UIImage? {
        guard let url = directory?.appendingPathComponent(fileName) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// 新しい画像を書き込み、使われなくなった画像を消してから、payload を保存する
    static func save(_ payload: WidgetPayload, newImages: [String: Data]) {
        guard let directory else { return }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in newImages {
            try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        let inUse = Set(payload.blocks.compactMap(\.inkImageFile))
        if let files = try? fileManager.contentsOfDirectory(atPath: directory.path) {
            for file in files where file.hasSuffix(".jpg") && !inUse.contains(file) {
                try? fileManager.removeItem(at: directory.appendingPathComponent(file))
            }
        }
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: directory.appendingPathComponent("payload.json"), options: .atomic)
        }
    }
}
