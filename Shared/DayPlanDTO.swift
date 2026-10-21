import Foundation

/// アプリの外に出す「1日の計画と実績」の形。
/// App Intents（v0.2）と MCP サーバー（v0.3）で同じ形を使い回す。
/// サーバー側の定義は server/src/dto.ts（項目名・値をそろえること）。
struct DayPlanDTO: Codable, Hashable, Sendable {
    /// "YYYY-MM-DD"（Asia/Tokyo）
    var date: String
    var cards: [Card]

    struct Card: Codable, Hashable, Sendable {
        var id: String
        /// 文字起こし
        var text: String
        /// "HH:mm"（Asia/Tokyo）
        var start: String
        var end: String
        var category: String
        /// planned / done / not_done / carried / skipped
        var status: String
        var actualStart: String?
        var actualEnd: String?
        var carriedOverCount: Int
        var hasHandwritingImage: Bool

        /// JSON の項目名（エンコーダー・デコーダーがスネークケースに変える：actualStart → actual_start）
        enum CodingKeys: String, CodingKey {
            case id, text, start, end, category, status, actualStart, actualEnd, carriedOverCount, hasHandwritingImage
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func jsonString() -> String {
        guard let data = try? Self.encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension DayPlanDTO.Card {
    /// AI が書いた JSON では id や状態が抜けていることが多いので、なくても読めるようにする。
    /// 必須は start だけ。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        start = try container.decode(String.self, forKey: .start)
        end = try container.decodeIfPresent(String.self, forKey: .end) ?? ""
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "planned"
        actualStart = try container.decodeIfPresent(String.self, forKey: .actualStart)
        actualEnd = try container.decodeIfPresent(String.self, forKey: .actualEnd)
        carriedOverCount = try container.decodeIfPresent(Int.self, forKey: .carriedOverCount) ?? 0
        hasHandwritingImage = try container.decodeIfPresent(Bool.self, forKey: .hasHandwritingImage) ?? false
    }

    /// サーバー（MCP）と同じ形にするため、値がないときも "actual_start": null のように書き出す
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(category, forKey: .category)
        try container.encode(status, forKey: .status)
        try container.encode(actualStart, forKey: .actualStart)
        try container.encode(actualEnd, forKey: .actualEnd)
        try container.encode(carriedOverCount, forKey: .carriedOverCount)
        try container.encode(hasHandwritingImage, forKey: .hasHandwritingImage)
    }
}
