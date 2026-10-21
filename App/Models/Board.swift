import Foundation
import SwiftData
import UIKit

enum BoardKind: String, CaseIterable {
    case whiteboard
    case notebook
    case paper

    var label: String {
        switch self {
        case .whiteboard: return "ホワイトボード"
        case .notebook: return "ノート"
        case .paper: return "紙"
        }
    }
}

/// 同じ場所に書き続けるボード（例：自室ホワイトボード）
@Model
final class Board: SyncTracked {
    var id: UUID = UUID()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    var name: String = ""
    var kindRaw: String = "whiteboard"
    var createdAt: Date = Date()
    /// 定点撮影で半透明に重ねる、前回の写真
    @Attribute(.externalStorage) var referencePhoto: Data?

    @Relationship(deleteRule: .cascade, inverse: \Snapshot.board)
    var snapshots: [Snapshot]? = []

    init(name: String, kind: BoardKind) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }
}

extension Board {
    var kind: BoardKind {
        get { BoardKind(rawValue: kindRaw) ?? .whiteboard }
        set { kindRaw = newValue.rawValue; touch() }
    }

    var referenceImage: UIImage? { referencePhoto.flatMap(UIImage.init(data:)) }

    /// 最初のボード。なければ「自室ボード」を作る。
    static func defaultBoard(in context: ModelContext) -> Board {
        let descriptor = FetchDescriptor<Board>(sortBy: [SortDescriptor(\.createdAt)])
        if let board = (try? context.fetch(descriptor))?.alive.first {
            return board
        }
        let board = Board(name: "自室ボード", kind: .whiteboard)
        context.insert(board)
        return board
    }
}
