import UIKit

/// The extra-work report as one tall picture, for sending through a chat.
///
/// A4 PDFs open in WhatsApp zoomed in on the top of the page and cut off at
/// the sides; a picture opens full width. So this is the PDF's report — the
/// same blocks in the same order, in the export language, drawn by the same
/// `ExtraWorkReportLayout` — on one page 1080 pixels wide with the text at
/// about 30 pixels, as tall as the report needs and never cut into pages.
/// The footer says "Zeitkonto" without a page count.
///
/// Photos are small thumbnails, as in the PDF, until the picture would grow
/// taller than `photoHeightLimit`: then they are left out and the text is
/// kept, since a chat shrinks a very tall picture until it cannot be read,
/// and the PDF still carries them. The bytes are a PNG or a JPEG at 0.85,
/// whichever is smaller: a page of text is crisper and usually smaller as a
/// PNG, a page of photos smaller as a JPEG.
enum ExtraWorkPictureRenderer {
    struct Picture {
        let data: Data
        /// "png" or "jpg".
        let fileExtension: String
        /// In pixels.
        let size: CGSize
    }

    static let metrics = ExtraWorkReportLayout.Metrics.picture
    /// The tallest the picture may be with its photos, in pixels: about
    /// fifteen phone screens. Past it the photos are left out.
    static let photoHeightLimit: CGFloat = 16_000
    static let jpegQuality: CGFloat = 0.85

    /// - Parameter photos: small JPEGs by photo id
    ///   (`DiaryPhotoProcessor.thumbnailPrintJPEG`), as the PDF takes them.
    static func picture(for document: ExtraWorkDocument, photos: [UUID: Data] = [:]) -> Picture {
        let drawn = Self.image(for: document, photos: photos)
        let png = drawn.pngData() ?? Data()
        if let jpeg = drawn.jpegData(compressionQuality: jpegQuality), png.isEmpty || jpeg.count < png.count {
            return Picture(data: jpeg, fileExtension: "jpg", size: pixelSize(of: drawn))
        }
        return Picture(data: png, fileExtension: "png", size: pixelSize(of: drawn))
    }

    /// The picture before it is encoded.
    static func image(for document: ExtraWorkDocument, photos: [UUID: Data] = [:]) -> UIImage {
        let images = photos.compactMapValues { DiaryPhotoProcessor.printableImage(from: $0) }
        var layout = ExtraWorkReportLayout(document: document, images: images, metrics: metrics)
        if !images.isEmpty && height(of: layout) > photoHeightLimit {
            layout = ExtraWorkReportLayout(document: document, images: [:], metrics: metrics)
        }
        let size = CGSize(width: metrics.pageWidth, height: height(of: layout))

        let format = UIGraphicsImageRendererFormat()
        // A point is a pixel: the metrics are already in pixels.
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            // Paper, whatever the phone's appearance.
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            var y = metrics.top
            for block in layout.blocks {
                y = layout.draw(block, at: y)
            }
            let closingBottom = y + layout.closingHeight
            layout.drawClosing(above: closingBottom)
            layout.drawFooter("Zeitkonto", below: closingBottom)
        }
    }

    /// Top margin, every block, the closing, the footer line, the bottom
    /// margin: whole pixels.
    private static func height(of layout: ExtraWorkReportLayout) -> CGFloat {
        let blocks = layout.blocks.reduce(CGFloat(0)) { $0 + layout.height(of: $1) }
        return ceil(metrics.top + blocks + layout.closingHeight + layout.footerLine + metrics.bottom)
    }

    private static func pixelSize(of image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }
}
