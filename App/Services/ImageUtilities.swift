import UIKit

/// 画像をデコードしたものを覚えておく（一覧をスクロールするたびにデコードしないため）
enum ImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for key: String, data: () -> Data?) -> UIImage? {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let data = data(), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}

extension UIImage {
    /// 向きの情報（EXIF）を反映して、上向きの画像に描き直す
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 長い辺が maxDimension ピクセル以下になるよう縮小する
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let pixelWidth = size.width * scale, pixelHeight = size.height * scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxDimension else { return self }
        let ratio = maxDimension / longest
        let newSize = CGSize(width: (pixelWidth * ratio).rounded(), height: (pixelHeight * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// インクのある領域を探して切り出す（ウィジェット用）。
/// カード全体を縮小すると字が潰れるので、筆跡のある部分だけを残す。
enum InkCropper {
    /// インクのある領域（0〜1、左上が原点）。見つからなければ nil。
    static func inkRect(in image: CGImage) -> CGRect? {
        let width = 160
        let height = max(1, Int(Double(image.height) * Double(width) / Double(max(image.width, 1))))
        let marginX = max(1, width * 3 / 100), marginY = max(1, height * 3 / 100)
        guard width > marginX * 2, height > marginY * 2,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)

        // 背景の明るさ＝明るさの中央値（ボードは背景のほうが面積が広い）
        var histogram = [Int](repeating: 0, count: 256)
        for index in 0..<(width * height) { histogram[Int(pixels[index])] += 1 }
        var accumulated = 0, median = 255
        for value in 0..<256 {
            accumulated += histogram[value]
            if accumulated >= width * height / 2 { median = value; break }
        }
        let threshold = median - max(28, median / 6)
        guard threshold > 0 else { return nil }

        // 端の影を拾わないよう、外周3%は見ない
        var rowCounts = [Int](repeating: 0, count: height)
        var columnCounts = [Int](repeating: 0, count: width)
        for y in marginY..<(height - marginY) {
            for x in marginX..<(width - marginX) where Int(pixels[y * width + x]) < threshold {
                rowCounts[y] += 1
                columnCounts[x] += 1
            }
        }
        // 小さな汚れを無視する
        let minimumInRow = max(1, width / 100), minimumInColumn = max(1, height / 100)
        guard let top = rowCounts.firstIndex(where: { $0 >= minimumInRow }),
              let bottom = rowCounts.lastIndex(where: { $0 >= minimumInRow }),
              let left = columnCounts.firstIndex(where: { $0 >= minimumInColumn }),
              let right = columnCounts.lastIndex(where: { $0 >= minimumInColumn }) else { return nil }

        let rect = CGRect(
            x: Double(left) / Double(width),
            y: Double(top) / Double(height),
            width: Double(right - left + 1) / Double(width),
            height: Double(bottom - top + 1) / Double(height)
        )
        return rect.insetBy(dx: -0.06, dy: -0.06).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    static func croppedToInk(_ image: UIImage, maxDimension: CGFloat = 480) -> UIImage {
        guard let cgImage = image.cgImage else { return image.downscaled(maxDimension: maxDimension) }
        let normalized = inkRect(in: cgImage) ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let pixelRect = CGRect(
            x: normalized.minX * CGFloat(cgImage.width),
            y: normalized.minY * CGFloat(cgImage.height),
            width: normalized.width * CGFloat(cgImage.width),
            height: normalized.height * CGFloat(cgImage.height)
        ).integral
        guard let cropped = cgImage.cropping(to: pixelRect) else { return image.downscaled(maxDimension: maxDimension) }
        return UIImage(cgImage: cropped).downscaled(maxDimension: maxDimension)
    }
}
