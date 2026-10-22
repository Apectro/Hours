import UIKit
import ImageIO

/// Makes a photo fit for the diary: small, and with nothing in it but the
/// picture.
///
/// Every image is decoded and written again as a new JPEG with no metadata
/// at all, which is what takes the location out. A phone photo carries GPS
/// coordinates in its EXIF block, and the app promises no location access;
/// keeping someone's whereabouts in a file they hand a director would break
/// that promise by the back door. Re-encoding rather than editing the EXIF
/// means there is no list of tags to get wrong: nothing is copied across.
enum DiaryPhotoProcessor {
    /// The longest side of a stored photo, in pixels. Enough to read a
    /// delivery note in the picture; small enough for a backup.
    static let longEdge: CGFloat = 1600
    static let quality: CGFloat = 0.7

    /// The longest side of a photo printed in the director's PDF.
    static let printLongEdge: CGFloat = 900
    static let printQuality: CGFloat = 0.6

    /// A picked photo (any format the system reads: HEIC, JPEG, PNG) as a
    /// stored JPEG, upright, at most `longEdge`, without metadata.
    static func storedJPEG(from data: Data) -> Data? {
        reencoded(data, maxPixel: longEdge, quality: quality)
    }

    /// A photo from the camera. Drawn into a new image at the stored size,
    /// which applies its orientation and leaves its metadata behind.
    static func storedJPEG(from image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, longEdge / max(size.width, size.height))
        let target = CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    /// A smaller JPEG for the PDF. Drawn from JPEG data, a PDF keeps the
    /// compressed bytes as they are rather than storing every pixel, so a
    /// month of photos stays a file that can be emailed.
    static func printJPEG(from data: Data) -> Data? {
        reencoded(data, maxPixel: printLongEdge, quality: printQuality)
    }

    /// The longest side of a photo printed as a thumbnail beside a job on
    /// the extra-work report, where it is drawn about an inch wide.
    static let thumbnailPrintLongEdge: CGFloat = 360

    /// A small JPEG for a thumbnail in a PDF: the extra-work report prints
    /// up to six per job, small, and full-size photos would only swell it.
    static func thumbnailPrintJPEG(from data: Data) -> Data? {
        reencoded(data, maxPixel: thumbnailPrintLongEdge, quality: printQuality)
    }

    /// An image for the screen, decoded at no more than `maxPixel`.
    static func thumbnail(from data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let image = downsampled(data, maxPixel: maxPixel) else { return nil }
        return UIImage(cgImage: image)
    }

    /// An image whose bytes are the JPEG itself, for drawing into a PDF.
    static func printableImage(from jpeg: Data) -> UIImage? {
        guard
            let provider = CGDataProvider(data: jpeg as CFData),
            let image = CGImage(
                jpegDataProviderSource: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else { return UIImage(data: jpeg) }
        return UIImage(cgImage: image)
    }

    // MARK: - Helpers

    private static func downsampled(_ data: Data, maxPixel: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Upright, whatever way the phone was held.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func reencoded(_ data: Data, maxPixel: CGFloat, quality: CGFloat) -> Data? {
        guard let image = downsampled(data, maxPixel: maxPixel) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        // Only the quality: no properties dictionary from the source is
        // passed, so no EXIF, GPS or maker notes are written.
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
