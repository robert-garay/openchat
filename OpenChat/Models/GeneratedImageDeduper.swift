import Foundation
#if canImport(UIKit)
import UIKit
#endif
import CoreGraphics

/// Collapses generated-image twins: exact copies and near-identical designs.
/// Distinct compositions, palettes, or layouts are kept. First occurrence wins.
enum GeneratedImageDeduper {
    /// Max dHash Hamming distance (64-bit) still treated as the same design.
    static let maxHammingDistance = 8
    /// Max Euclidean distance between mean RGB (0–255) still treated as the same design.
    static let maxMeanColorDistance: Double = 20

    static func unique(from images: [ChatImageAttachment]) -> [ChatImageAttachment] {
        merging(images, into: [])
    }

    static func merging(_ incoming: [ChatImageAttachment], into existing: [ChatImageAttachment]) -> [ChatImageAttachment] {
        var kept: [ChatImageAttachment] = []
        var signatures: [Signature] = []

        func consider(_ image: ChatImageAttachment) {
            let signature = Signature(image)
            if signatures.contains(where: { $0.isNearDuplicate(of: signature) }) {
                return
            }
            kept.append(image)
            signatures.append(signature)
        }

        for image in existing {
            consider(image)
        }
        for image in incoming {
            consider(image)
        }
        return kept
    }

    private struct Signature: Sendable {
        let data: Data
        let metrics: PerceptualMetrics?

        init(_ image: ChatImageAttachment) {
            data = image.data
            metrics = PerceptualMetrics.compute(from: image.data)
        }

        func isNearDuplicate(of other: Signature) -> Bool {
            if data == other.data { return true }
            guard let metrics, let otherMetrics = other.metrics else { return false }
            return metrics.isNearDuplicate(of: otherMetrics)
        }
    }
}

private struct PerceptualMetrics: Sendable {
    let dHash: UInt64
    let meanRed: Double
    let meanGreen: Double
    let meanBlue: Double

    func isNearDuplicate(of other: PerceptualMetrics) -> Bool {
        let hamming = (dHash ^ other.dHash).nonzeroBitCount
        guard hamming <= GeneratedImageDeduper.maxHammingDistance else { return false }
        let deltaRed = meanRed - other.meanRed
        let deltaGreen = meanGreen - other.meanGreen
        let deltaBlue = meanBlue - other.meanBlue
        let colorDistance = sqrt(deltaRed * deltaRed + deltaGreen * deltaGreen + deltaBlue * deltaBlue)
        return colorDistance <= GeneratedImageDeduper.maxMeanColorDistance
    }

    static func compute(from data: Data) -> PerceptualMetrics? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        return compute(from: image)
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    static func compute(from image: UIImage) -> PerceptualMetrics? {
        let width = 9
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = rasterCGImage(image) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luminance = [Int](repeating: 0, count: width * height)
        var sumRed = 0
        var sumGreen = 0
        var sumBlue = 0
        for row in 0..<height {
            for column in 0..<width {
                let offset = (row * width + column) * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                sumRed += red
                sumGreen += green
                sumBlue += blue
                luminance[row * width + column] = (red * 299 + green * 587 + blue * 114) / 1000
            }
        }

        var hash: UInt64 = 0
        var bit: UInt64 = 1
        for row in 0..<height {
            for column in 0..<(width - 1) {
                if luminance[row * width + column] > luminance[row * width + column + 1] {
                    hash |= bit
                }
                bit <<= 1
            }
        }

        let pixelCount = Double(width * height)
        return PerceptualMetrics(
            dHash: hash,
            meanRed: Double(sumRed) / pixelCount,
            meanGreen: Double(sumGreen) / pixelCount,
            meanBlue: Double(sumBlue) / pixelCount
        )
    }

    private static func rasterCGImage(_ image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage { return cgImage }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(at: .zero)
        }.cgImage
    }
    #endif
}
