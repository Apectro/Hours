import UIKit

/// Draws the extra-work report as a PDF, in the look of the app's other
/// exports (mockup 16): the orange eyebrow ("EXTRA WORK DONE · dates"), the
/// site's name in bold, who recorded it, grey tiles, grey upper-case column
/// heads over thin rules, a heavier rule under the last line, and
/// "Zeitkonto · page 1 of 2".
///
/// It tells the boss what is done, so the work comes first and big: the
/// jobs day by day with their photos, then any still in progress under a
/// heading of their own, then the material used as a summary. Nothing on it
/// is a form: no empty lines to sign on. A signature the client gave is
/// drawn with "Confirmed on site by …" — on its job, or under the report —
/// and nothing is drawn where there is none.
///
/// A4 portrait, as the mockup is: a report of jobs and material is read
/// down the page, unlike a month of hours, which needs the width. Type,
/// colours, the text helpers and the signature drawing are the director's
/// sheet's own (`PDFReportStyle`, `PDFAppendix.drawStrokes`). Laid out
/// before drawing, as that sheet is, so the footer knows the page count;
/// jobs that do not fit carry on over the next pages under their headings
/// again.
enum ExtraWorkPDFRenderer {
    static let pageSize = CGSize(width: 595, height: 842)

    private static let margin: CGFloat = 36
    private static let top: CGFloat = 34
    private static let bottom: CGFloat = 24
    private static var width: CGFloat { pageSize.width - margin * 2 }
    /// The page count line at the foot of every page.
    private static let footerLine: CGFloat = 14
    private static var contentBottom: CGFloat { pageSize.height - bottom - footerLine }

    private static let headerHeight: CGFloat = 74
    private static let sectionGap: CGFloat = 18
    private static let sectionTitleHeight: CGFloat = 14
    private static let columnHeadHeight: CGFloat = 18
    private static let materialRowHeight: CGFloat = 17
    private static let rowPadding: CGFloat = 6
    private static let thumbnail: CGFloat = 32
    private static let thumbnailGap: CGFloat = 4
    private static let closingHeight: CGFloat = 70
    /// A job's own signature, drawn under its confirmation line.
    private static let jobSignatureHeight: CGFloat = 26
    private static let jobSignatureWidth: CGFloat = 90

    private static let tileWidth: CGFloat = 76
    private static let tileHeight: CGFloat = 40
    private static let tileGap: CGFloat = 6

    // Job columns: day, work and material, photos.
    private static let dayWidth: CGFloat = 56
    private static let photosWidth: CGFloat = thumbnail * 3 + thumbnailGap * 2 + 12
    private static var workWidth: CGFloat { width - dayWidth - photosWidth }

    private enum Block: Hashable {
        case header
        case jobsHead
        case job(Int)
        case progressHead
        case progressJob(Int)
        case materialHead
        case material(Int)

        var isHeading: Bool { self == .jobsHead || self == .progressHead || self == .materialHead }
    }

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
        let pages = layOut(document, images: images)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                var y = top
                for block in page.blocks {
                    y = draw(block, of: document, images: images, at: y)
                }
                if page.closes { drawClosing(document) }
                drawPageNumber(index + 1, of: pages.count, language: document.language)
            }
        }
    }

    // MARK: - Layout

    private static func height(of block: Block, in document: ExtraWorkDocument, images: [UUID: UIImage]) -> CGFloat {
        switch block {
        case .header: return headerHeight(for: document)
        case .jobsHead, .progressHead, .materialHead: return sectionGap + sectionTitleHeight + columnHeadHeight
        case .material: return materialRowHeight
        case let .job(index): return jobHeight(document.jobs[index], images: images)
        case let .progressJob(index): return jobHeight(document.inProgressJobs[index], images: images)
        }
    }

    /// The work done first, what is still in progress after it, the
    /// material last.
    private static func layOut(_ document: ExtraWorkDocument, images: [UUID: UIImage]) -> [Page] {
        var blocks: [Block] = [.header]
        if !document.jobs.isEmpty {
            blocks.append(.jobsHead)
            blocks += document.jobs.indices.map(Block.job)
        }
        if !document.inProgressJobs.isEmpty {
            blocks.append(.progressHead)
            blocks += document.inProgressJobs.indices.map(Block.progressJob)
        }
        if !document.material.isEmpty {
            blocks.append(.materialHead)
            blocks += document.material.indices.map(Block.material)
        }

        var pages: [Page] = []
        var page = Page()
        var y = top
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            var needed = height(of: block, in: document, images: images)
            // A heading never ends a page alone: it goes over with its first row.
            if block.isHeading, index + 1 < blocks.count {
                needed += height(of: blocks[index + 1], in: document, images: images)
            }
            if y + needed > contentBottom && !page.blocks.isEmpty && !isHeadingOnly(page) {
                pages.append(page)
                page = Page()
                y = top
                // Rows that carry on over a page carry their heading with them.
                switch block {
                case .material: page.blocks.append(.materialHead)
                case .job: page.blocks.append(.jobsHead)
                case .progressJob: page.blocks.append(.progressHead)
                default: break
                }
                y += page.blocks.reduce(0) { $0 + height(of: $1, in: document, images: images) }
            }
            page.blocks.append(block)
            y += height(of: block, in: document, images: images)
            index += 1
        }
        // The legend, and the client's signature if there is one, close the
        // last page, or a page of their own when the last one is full.
        if y + closingHeight <= pageSize.height - bottom - footerLine {
            page.closes = true
            pages.append(page)
        } else {
            pages.append(page)
            pages.append(Page(blocks: [], closes: true))
        }
        return pages
    }

    private static func isHeadingOnly(_ page: Page) -> Bool {
        page.blocks.allSatisfy(\.isHeading)
    }

    // MARK: - Measuring

    private static func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(bounds.height)
    }

    private static func textLines(of job: ExtraWorkDocument.JobRow) -> [(String, UIFont, UIColor)] {
        [
            (job.description, PDFReportStyle.cellBoldFont, PDFReportStyle.ink),
            (job.material, PDFReportStyle.cellFont, PDFReportStyle.ink),
            (job.hours, PDFReportStyle.cellFont, PDFReportStyle.secondary),
            (job.confirmation, PDFReportStyle.smallFont, PDFReportStyle.secondary)
        ].filter { !$0.0.isEmpty }
    }

    private static func photoRows(_ job: ExtraWorkDocument.JobRow, images: [UUID: UIImage]) -> Int {
        let count = job.photoIDs.filter { images[$0] != nil }.count
        return (count + 2) / 3
    }

    private static func jobHeight(_ job: ExtraWorkDocument.JobRow, images: [UUID: UIImage]) -> CGFloat {
        let inner = workWidth - PDFReportStyle.cellPadding * 2
        var text = textLines(of: job).reduce(CGFloat(0)) { $0 + textHeight($1.0, font: $1.1, width: inner) + 2 }
        if job.signature != nil { text += jobSignatureHeight }
        let rows = photoRows(job, images: images)
        let photos = rows == 0 ? 0 : CGFloat(rows) * thumbnail + CGFloat(rows - 1) * thumbnailGap
        return max(text, photos, PDFReportStyle.cellFont.lineHeight) + rowPadding * 2
    }

    // MARK: - Drawing

    private static func draw(_ block: Block, of document: ExtraWorkDocument, images: [UUID: UIImage], at y: CGFloat) -> CGFloat {
        switch block {
        case .header:
            drawHeader(document, at: y)
        case .jobsHead, .progressHead:
            drawSection(
                block == .jobsHead ? document.jobsHeading : document.inProgressHeading,
                columns: [(document.jobHeadings[0], dayWidth, .left),
                          (document.jobHeadings[1], workWidth, .left),
                          (document.jobHeadings[2], photosWidth, .left)],
                language: document.language,
                at: y
            )
        case let .job(index):
            drawJob(document.jobs[index], isLast: index == document.jobs.count - 1, images: images, at: y)
        case let .progressJob(index):
            drawJob(document.inProgressJobs[index], isLast: index == document.inProgressJobs.count - 1, images: images, at: y)
        case .materialHead:
            drawSection(
                document.materialHeading,
                columns: [(document.materialHeadings[0], width - 140, .left),
                          (document.materialHeadings[1], 80, .right),
                          (document.materialHeadings[2], 60, .left)],
                language: document.language,
                at: y
            )
        case let .material(index):
            drawMaterial(document.material[index], isLast: index == document.material.count - 1, at: y)
        }
        return y + height(of: block, in: document, images: images)
    }

    private static func tileRowWidth(_ document: ExtraWorkDocument) -> CGFloat {
        let count = CGFloat(document.tiles.count)
        return count == 0 ? 0 : count * tileWidth + (count - 1) * tileGap
    }

    /// Whether the site's name fits beside the tiles. Four tiles leave under
    /// 200 points, which cut "Trg Pravde Zagreb" short at the title's size; a
    /// name that does not fit gets the full width and the tiles a row of their
    /// own under the byline, rather than an ellipsis in the one word the boss
    /// files the sheet by.
    private static func titleFitsBesideTiles(_ document: ExtraWorkDocument) -> Bool {
        let room = width - tileRowWidth(document) - (document.tiles.isEmpty ? 0 : 12)
        let needed = (document.title as NSString).size(withAttributes: [.font: PDFReportStyle.titleFont]).width
        return needed <= room
    }

    private static func headerHeight(for document: ExtraWorkDocument) -> CGFloat {
        titleFitsBesideTiles(document) ? headerHeight : headerHeight + tileHeight + 8
    }

    private static func drawHeader(_ document: ExtraWorkDocument, at y: CGFloat) {
        let tiles = document.tiles
        let besides = titleFitsBesideTiles(document)
        let tilesWidth = tileRowWidth(document)
        let textWidth = besides ? width - tilesWidth - (tiles.isEmpty ? 0 : 12) : width

        PDFReportStyle.draw(
            document.eyebrow.uppercased(with: document.language.locale),
            in: CGRect(x: margin, y: y, width: textWidth, height: 11),
            font: PDFReportStyle.eyebrowFont,
            color: PDFReportStyle.accent,
            kern: 0.8
        )
        PDFReportStyle.draw(
            document.title,
            in: CGRect(x: margin, y: y + 12, width: textWidth, height: 30),
            font: PDFReportStyle.titleFont,
            color: PDFReportStyle.ink
        )
        PDFReportStyle.drawWrapping(
            document.byline,
            // Under the tiles, which end above it, so it has the full width:
            // squeezed beside four tiles it broke in the middle of a name.
            in: CGRect(x: margin, y: y + 43, width: width, height: 24),
            font: PDFReportStyle.bylineFont,
            color: PDFReportStyle.secondary
        )

        var x = besides ? margin + width - tilesWidth : margin
        let tilesTop = besides ? y : y + 66
        for tile in tiles {
            let rect = CGRect(x: x, y: tilesTop, width: tileWidth, height: tileHeight)
            PDFReportStyle.tile.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
            PDFReportStyle.draw(tile.label, in: CGRect(x: x + 8, y: tilesTop + 5, width: tileWidth - 16, height: 10),
                                font: PDFReportStyle.tileLabelFont, color: PDFReportStyle.secondary)
            PDFReportStyle.draw(tile.value, in: CGRect(x: x + 8, y: tilesTop + 16, width: tileWidth - 16, height: 21),
                                font: PDFReportStyle.tileValueFont, color: PDFReportStyle.ink)
            x += tileWidth + tileGap
        }

        let ruleY = y + headerHeight(for: document) - 6
        PDFReportStyle.line(from: CGPoint(x: margin, y: ruleY), to: CGPoint(x: margin + width, y: ruleY),
                            width: 2, color: PDFReportStyle.ink)
    }

    /// "WORK DONE, DAY BY DAY", then the column heads over a thin dark rule.
    private static func drawSection(
        _ title: String,
        columns: [(String, CGFloat, NSTextAlignment)],
        language: ExportLanguage,
        at start: CGFloat
    ) {
        var y = start + sectionGap
        PDFReportStyle.draw(title.uppercased(with: language.locale), in: CGRect(x: margin, y: y, width: width, height: sectionTitleHeight),
                            font: PDFReportStyle.headingFont, color: PDFReportStyle.secondary, kern: 0.3)
        y += sectionTitleHeight
        var x = margin
        let padding = PDFReportStyle.cellPadding
        for (heading, columnWidth, alignment) in columns {
            PDFReportStyle.draw(heading.uppercased(with: language.locale),
                                in: CGRect(x: x + padding, y: y, width: columnWidth - padding * 2, height: columnHeadHeight),
                                font: PDFReportStyle.headingFont, color: PDFReportStyle.secondary, alignment: alignment, kern: 0.3)
            x += columnWidth
        }
        PDFReportStyle.line(from: CGPoint(x: margin, y: y + columnHeadHeight), to: CGPoint(x: margin + width, y: y + columnHeadHeight),
                            width: 0.8, color: PDFReportStyle.ink)
    }

    private static func rowRule(at y: CGFloat, isLast: Bool) {
        PDFReportStyle.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y),
                            width: isLast ? 1.2 : 0.5, color: isLast ? PDFReportStyle.ink : PDFReportStyle.rule)
    }

    private static func drawMaterial(_ line: ExtraWorkDocument.MaterialRow, isLast: Bool, at y: CGFloat) {
        let padding = PDFReportStyle.cellPadding
        let nameWidth = width - 140
        PDFReportStyle.draw(line.name, in: CGRect(x: margin + padding, y: y, width: nameWidth - padding * 2, height: materialRowHeight),
                            font: PDFReportStyle.cellFont, color: PDFReportStyle.ink)
        PDFReportStyle.draw(line.quantity, in: CGRect(x: margin + nameWidth + padding, y: y, width: 80 - padding * 2, height: materialRowHeight),
                            font: PDFReportStyle.cellBoldFont, color: PDFReportStyle.ink, alignment: .right)
        PDFReportStyle.draw(line.unit, in: CGRect(x: margin + nameWidth + 80 + padding, y: y, width: 60 - padding * 2, height: materialRowHeight),
                            font: PDFReportStyle.cellFont, color: PDFReportStyle.secondary)
        rowRule(at: y + materialRowHeight, isLast: isLast)
    }

    private static func drawJob(_ job: ExtraWorkDocument.JobRow, isLast: Bool, images: [UUID: UIImage], at start: CGFloat) {
        let rowHeight = jobHeight(job, images: images)
        let padding = PDFReportStyle.cellPadding
        let y = start + rowPadding

        PDFReportStyle.draw(job.day, in: CGRect(x: margin + padding, y: y, width: dayWidth - padding * 2, height: 12),
                            font: PDFReportStyle.cellBoldFont, color: PDFReportStyle.ink)

        let workX = margin + dayWidth + padding
        let inner = workWidth - padding * 2
        var textY = y
        for (text, font, color) in textLines(of: job) {
            let height = textHeight(text, font: font, width: inner)
            PDFReportStyle.drawWrapping(text, in: CGRect(x: workX, y: textY, width: inner, height: height + 2), font: font, color: color)
            textY += height + 2
        }
        if let signature = job.signature {
            let area = CGRect(x: workX, y: textY, width: jobSignatureWidth, height: jobSignatureHeight - 2)
            PDFAppendix.drawStrokes(signature.strokes, aspectRatio: signature.aspectRatio, in: area)
        }

        let photosX = margin + dayWidth + workWidth + padding
        let shown = job.photoIDs.compactMap { images[$0] }
        if shown.isEmpty {
            PDFReportStyle.draw("—", in: CGRect(x: photosX, y: y, width: 20, height: 12),
                                font: PDFReportStyle.cellFont, color: PDFReportStyle.faint)
        } else {
            for (index, image) in shown.enumerated() {
                let cell = CGRect(
                    x: photosX + CGFloat(index % 3) * (thumbnail + thumbnailGap),
                    y: y + CGFloat(index / 3) * (thumbnail + thumbnailGap),
                    width: thumbnail,
                    height: thumbnail
                )
                drawFilled(image, in: cell)
            }
        }


        rowRule(at: start + rowHeight, isLast: isLast)
    }

    /// A photo cropped to fill its square, with rounded corners.
    private static func drawFilled(_ image: UIImage, in cell: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(cell.width / image.size.width, cell.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let frame = CGRect(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2, width: size.width, height: size.height)
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(roundedRect: cell, cornerRadius: 3).addClip()
        image.draw(in: frame)
        UIGraphicsGetCurrentContext()?.restoreGState()
    }

    /// The legend on the left; on the right, the client's signature under
    /// the whole report with "Confirmed on site by …", when they gave one.
    /// No empty lines: this is a report, not a form.
    private static func drawClosing(_ document: ExtraWorkDocument) {
        let lineY = pageSize.height - bottom - footerLine - 14
        let areaTop = lineY - closingHeight + 20
        let signatureWidth: CGFloat = 220
        let gap: CGFloat = 18
        let legendWidth = document.clientSignature == nil ? width : width - signatureWidth - gap

        PDFReportStyle.drawWrapping(document.legend, in: CGRect(x: margin, y: lineY - 34, width: max(120, legendWidth), height: 46),
                                    font: PDFReportStyle.smallFont, color: PDFReportStyle.secondary)

        if let signature = document.clientSignature {
            let x = margin + legendWidth + gap
            let area = CGRect(x: x, y: areaTop, width: signatureWidth, height: lineY - areaTop - 2)
            PDFAppendix.drawStrokes(signature.strokes, aspectRatio: signature.aspectRatio, in: area)
            PDFReportStyle.line(from: CGPoint(x: x, y: lineY), to: CGPoint(x: x + signatureWidth, y: lineY),
                                width: 0.6, color: PDFReportStyle.signatureRule)
            // One line, above the page count: 7.5 pt fits "Confirmed on site
            // by" a long name and a date in this width.
            PDFReportStyle.draw(document.clientSignatureLabel, in: CGRect(x: x, y: lineY + 1, width: signatureWidth, height: 11),
                                font: PDFReportStyle.smallFont, color: PDFReportStyle.secondary)
        }
    }

    private static func drawPageNumber(_ page: Int, of count: Int, language: ExportLanguage) {
        let text = ["Zeitkonto", language.pageOf(page, count)].joined(separator: " · ")
        PDFReportStyle.draw(text, in: CGRect(x: margin, y: pageSize.height - bottom - 10, width: width, height: 10),
                            font: PDFReportStyle.footerFont, color: PDFReportStyle.faint, alignment: .right)
    }
}
