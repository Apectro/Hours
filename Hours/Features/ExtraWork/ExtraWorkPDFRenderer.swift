import UIKit

/// Draws the extra-work report as a PDF, in the look of the app's other
/// exports (mockup 16): the orange eyebrow ("EXTRA WORK DONE · dates"), the
/// site's name in bold, who recorded it, grey tiles, grey upper-case column
/// heads over thin rules, a heavier rule under the last line, and
/// "Zeitkonto · page 1 of 2".
///
/// It tells the boss what is done, so the work comes first and big: the
/// jobs day by day with their photos (each item on a line of its own, then
/// how long the job took and who), then any still in progress under a
/// heading of their own, then the material used as a summary. Nothing on it
/// is a form: no empty lines to sign on. A signature the client gave is
/// drawn with "Confirmed on site by …" — on its job, or under the report —
/// and nothing is drawn where there is none.
///
/// A4 portrait, as the mockup is: a report of jobs and material is read
/// down the page, unlike a month of hours, which needs the width. What is
/// measured and drawn is `ExtraWorkReportLayout`, shared with the picture
/// for a chat (`ExtraWorkPictureRenderer`); this type only cuts its blocks
/// into pages. Laid out before drawing, as the director's sheet is, so the
/// footer knows the page count; jobs that do not fit carry on over the next
/// pages under their headings again.
enum ExtraWorkPDFRenderer {
    static let pageSize = CGSize(width: 595, height: 842)

    private static let metrics = ExtraWorkReportLayout.Metrics.pdf

    private typealias Block = ExtraWorkReportLayout.Block

    private struct Page {
        var blocks: [Block] = []
        var closes = false
    }

    // MARK: - Rendering

    /// - Parameter photos: small JPEGs by photo id
    ///   (`DiaryPhotoProcessor.thumbnailPrintJPEG`).
    static func data(for document: ExtraWorkDocument, photos: [UUID: Data] = [:]) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: document.documentTitle,
            kCGPDFContextCreator as String: "Zeitkonto"
        ]
        let images = photos.compactMapValues { DiaryPhotoProcessor.printableImage(from: $0) }
        let layout = ExtraWorkReportLayout(document: document, images: images, metrics: metrics)
        let pages = layOut(layout)
        let closingBottom = pageSize.height - metrics.bottom - layout.footerLine
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                var y = metrics.top
                for block in page.blocks {
                    y = layout.draw(block, at: y)
                }
                if page.closes { layout.drawClosing(above: closingBottom) }
                let footer = ["Zeitkonto", document.language.pageOf(index + 1, pages.count)].joined(separator: " · ")
                layout.drawFooter(footer, below: closingBottom)
            }
        }
    }

    // MARK: - Pages

    private static func layOut(_ layout: ExtraWorkReportLayout) -> [Page] {
        let blocks = layout.blocks
        let contentBottom = pageSize.height - metrics.bottom - layout.footerLine

        var pages: [Page] = []
        var page = Page()
        var y = metrics.top
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            var needed = layout.height(of: block)
            // A heading never ends a page alone: it goes over with its first row.
            if block.isHeading, index + 1 < blocks.count {
                needed += layout.height(of: blocks[index + 1])
            }
            if y + needed > contentBottom && !page.blocks.isEmpty && !page.blocks.allSatisfy(\.isHeading) {
                pages.append(page)
                page = Page()
                y = metrics.top
                // Rows that carry on over a page carry their heading with them.
                switch block {
                case .material: page.blocks.append(.materialHead)
                case .job: page.blocks.append(.jobsHead)
                case .progressJob: page.blocks.append(.progressHead)
                default: break
                }
                y += page.blocks.reduce(0) { $0 + layout.height(of: $1) }
            }
            page.blocks.append(block)
            y += layout.height(of: block)
            index += 1
        }
        // The legend, and the client's signature if there is one, close the
        // last page, or a page of their own when the last one is full.
        if y + layout.closingHeight <= contentBottom {
            page.closes = true
            pages.append(page)
        } else {
            pages.append(page)
            pages.append(Page(blocks: [], closes: true))
        }
        return pages
    }
}
