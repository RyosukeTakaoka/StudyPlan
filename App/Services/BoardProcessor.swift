import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// 確認画面で直す前の、カードの候補
struct CardDraft: Identifiable {
    let id = UUID()
    var image: UIImage?
    /// 補正後の写真の中での位置
    var rect: NormalizedRect
    var transcription: String
    var lines: [RecognizedLine]
    var start: Date
    var end: Date
    var category: BlockCategory
    /// 読み取りに自信がない理由。nil なら問題なし。確認画面で目立たせる。
    var reviewReason: String?

    var title: String { TimeParser.title(from: transcription) ?? category.label }
    var needsReview: Bool { reviewReason != nil }
}

/// 撮影した写真を処理した結果
struct ProcessedCapture: Identifiable, Hashable {
    let id = UUID()
    let original: UIImage
    let corrected: UIImage
    let didCorrect: Bool
    let day: Date
    let drafts: [CardDraft]

    static func == (lhs: ProcessedCapture, rhs: ProcessedCapture) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// 写真 → 台形補正 → 文字認識 → カードの区切りを提案。すべて端末内（Vision）で行う。
///
/// 完全自動は目指さない。区切りと時刻は提案にとどめ、確認画面でユーザーが直す。
enum BoardProcessor {
    static func process(_ image: UIImage, day: Date) async -> ProcessedCapture {
        await Task.detached(priority: .userInitiated) {
            processSync(image, day: day)
        }.value
    }

    static func processSync(_ image: UIImage, day: Date) -> ProcessedCapture {
        let upright = image.normalizedUp().downscaled(maxDimension: 2400)
        guard let cgImage = upright.cgImage else {
            return ProcessedCapture(original: upright, corrected: upright, didCorrect: false, day: day, drafts: [])
        }
        let (correctedCG, didCorrect) = correctPerspective(cgImage)
        let lines = recognizeLines(in: correctedCG)
        let drafts = proposeCards(from: lines, in: correctedCG, day: day)
        return ProcessedCapture(
            original: upright,
            corrected: UIImage(cgImage: correctedCG),
            didCorrect: didCorrect,
            day: day,
            drafts: drafts
        )
    }

    // MARK: - 枠の検出と台形補正

    static func correctPerspective(_ image: CGImage) -> (CGImage, Bool) {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.6
        request.minimumSize = 0.3
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        guard let rectangle = request.results?.first else { return (image, false) }

        // Vision も Core Image も左下が原点なので、そのまま掛け算でよい
        let width = CGFloat(image.width), height = CGFloat(image.height)
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * width, y: p.y * height) }
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = CIImage(cgImage: image)
        filter.topLeft = point(rectangle.topLeft)
        filter.topRight = point(rectangle.topRight)
        filter.bottomLeft = point(rectangle.bottomLeft)
        filter.bottomRight = point(rectangle.bottomRight)
        guard let output = filter.outputImage,
              let corrected = CIContext().createCGImage(output, from: output.extent) else { return (image, false) }
        return (corrected, true)
    }

    // MARK: - 文字認識

    /// 行ごとの文字と位置（写真全体に対する相対位置、左上が原点）
    static func recognizeLines(in image: CGImage) -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ja-JP", "en-US"]
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return RecognizedLine(
                text: candidate.string,
                confidence: candidate.confidence,
                rect: NormalizedRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            )
        }
    }

    // MARK: - カードの区切りを提案

    static func proposeCards(from lines: [RecognizedLine], in image: CGImage, day: Date) -> [CardDraft] {
        let sorted = lines.sorted { $0.rect.y < $1.rect.y }
        let nine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        guard !sorted.isEmpty else {
            return [CardDraft(
                image: UIImage(cgImage: image), rect: .full, transcription: "", lines: [],
                start: nine, end: nine.addingTimeInterval(3600), category: .study,
                reviewReason: "文字を読み取れませんでした。時刻と区切りを確認してください"
            )]
        }

        // 行の高さの中央値より大きなすき間、または時刻で始まる行で区切る
        let medianHeight = sorted.map(\.rect.height).sorted()[sorted.count / 2]
        var groups: [[RecognizedLine]] = []
        for line in sorted {
            guard let previous = groups.last?.last else { groups.append([line]); continue }
            let gap = line.rect.y - previous.rect.maxY
            let groupHasTime = groups[groups.count - 1].contains { TimeParser.firstTime(in: $0.text, on: day) != nil }
            if gap > medianHeight * 1.2 || (TimeParser.startsWithTime(line.text) && groupHasTime) {
                groups.append([line])
            } else {
                groups[groups.count - 1].append(line)
            }
        }

        // 時刻：書いてあればそれを使い、なければ前のカードの1時間後
        var starts: [Date] = []
        var reasons: [String?] = []
        for group in groups {
            let text = group.map(\.text).joined(separator: "\n")
            if let time = TimeParser.firstTime(in: text, on: day) {
                starts.append(time)
                let lowConfidence = group.contains { $0.confidence < 0.5 }
                reasons.append(lowConfidence ? "読み取りに自信がありません" : nil)
            } else {
                starts.append(starts.last.map { $0.addingTimeInterval(3600) } ?? nine)
                reasons.append("時刻を確認してください")
            }
        }

        let width = CGFloat(image.width), height = CGFloat(image.height)
        return groups.enumerated().map { (index, group) -> CardDraft in
            let union = group.dropFirst().reduce(group[0].rect) { $0.union($1.rect) }
            let rect = union.padded(dx: 0.02, dy: medianHeight * 0.4)
            let pixelRect = rect.cgRect(in: CGSize(width: width, height: height)).integral
            let start = starts[index]
            let nextStart = index + 1 < starts.count ? starts[index + 1] : nil
            let end = nextStart.flatMap { $0 > start ? $0 : nil } ?? start.addingTimeInterval(3600)
            let text = group.map(\.text).joined(separator: "\n")
            return CardDraft(
                image: image.cropping(to: pixelRect).map { UIImage(cgImage: $0) },
                rect: rect,
                transcription: text,
                lines: group.map { RecognizedLine(text: $0.text, confidence: $0.confidence, rect: $0.rect.relative(to: rect)) },
                start: start,
                end: end,
                category: BlockCategory.guess(from: text),
                reviewReason: reasons[index]
            )
        }
    }
}
