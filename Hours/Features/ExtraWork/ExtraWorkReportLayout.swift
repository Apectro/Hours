import UIKit

/// The extra-work report's one layout: what is measured and drawn, block by
/// block, for both renderings of it — the A4 PDF (`ExtraWorkPDFRenderer`),
/// which cuts the blocks into pages, and the tall picture for a chat
/// (`ExtraWorkPictureRenderer`), which draws them one under another.
///
/// The two differ only in `Metrics`: the page's width and margins, the
/// columns, and a type scale that every font, rule and vertical distance is
/// multiplied by. The PDF's metrics are the printed sheet's own (scale 1);
/// the picture's are wide in pixels and large in type, so the text is read
/// on a phone without zooming. Everything else — which blocks there are, in
/// which order, what each says — is this one type, so the two cannot drift
/// apart.
///
/// Type, colours, the text helpers and the signature drawing are the
/// director's sheet's (`PDFReportStyle`, `PDFAppendix.drawStrokes`).
struct ExtraWorkReportLayout {
    struct Metrics {
        /// Every font size, rule, kerning and vertical distance is
        /// multiplied by this; 1 is the printed page.
        var scale: CGFloat
        var pageWidth: CGFloat
        var margin: CGFloat
        var top: CGFloat
        var bottom: CGFloat
        /// The job columns: the day, and the photos (`thumbnailsPerRow`
        /// thumbnails of `thumbnail` points to a row). The work and its
        /// material take what is left.
        var dayWidth: CGFloat
        var thumbnail: CGFloat
        var thumbnailsPerRow: Int
        /// The material columns beside the name.
        var quantityWidth: CGFloat
        var unitWidth: CGFloat
        /// The item's barcode, when any item has one: an EAN-13 in the
        /// cell's monospaced digits, narrower than the name.
        var codeWidth: CGFloat
        /// The client's signature under the whole report.
        var signatureWidth: CGFloat
        var jobSignatureWidth: CGFloat

        /// The A4 page, as it always was.
        static let pdf = Metrics(
            scale: 1,
            pageWidth: 595,
            margin: 36,
            top: 34,
            bottom: 24,
            dayWidth: 56,
            thumbnail: 32,
            thumbnailsPerRow: 3,
            quantityWidth: 80,
            unitWidth: 60,
            codeWidth: 96,
            signatureWidth: 220,
            jobSignatureWidth: 90
        )

        /// 1080 pixels wide, drawn one point to a pixel, with the table's
        /// text at about 30 pixels: what a chat shows full width on a phone
        /// and can be read without zooming. Two thumbnails to a photo row
        /// leave the work its width.
        static let picture = Metrics(
            scale: 3.6,
            pageWidth: 1080,
            margin: 48,
            top: 56,
            bottom: 40,
            dayWidth: 150,
            thumbnail: 100,
            thumbnailsPerRow: 2,
            quantityWidth: 200,
            unitWidth: 150,
            codeWidth: 290,
            signatureWidth: 440,
            jobSignatureWidth: 324
        )
    }

    enum Block: Hashable {
        case header
        case jobsHead
        case job(Int)
        case progressHead
        case progressJob(Int)
        case materialHead
        case material(Int)

        var isHeading: Bool { self == .jobsHead || self == .progressHead || self == .materialHead }
    }

    let document: ExtraWorkDocument
    let images: [UUID: UIImage]
    let metrics: Metrics

    init(document: ExtraWorkDocument, images: [UUID: UIImage], metrics: Metrics) {
        self.document = document
        self.images = images
        self.metrics = metrics
    }

    // MARK: - Dimensions

    private var k: CGFloat { metrics.scale }
    private var margin: CGFloat { metrics.margin }
    var width: CGFloat { metrics.pageWidth - metrics.margin * 2 }
    /// The page count (or the app's name) at the very foot.
    var footerLine: CGFloat { 14 * k }
    /// The legend, and the client's signature when there is one.
    var closingHeight: CGFloat { 70 * k }

    private var headerBase: CGFloat { 74 * k }
    private var sectionGap: CGFloat { 18 * k }
    private var sectionTitleHeight: CGFloat { 14 * k }
    private var columnHeadHeight: CGFloat { 18 * k }
    private var materialRowHeight: CGFloat { 17 * k }
    private var rowPadding: CGFloat { 6 * k }
    private var thumbnailGap: CGFloat { 4 * k }
    private var jobSignatureHeight: CGFloat { 26 * k }
    private var cellPadding: CGFloat { PDFReportStyle.cellPadding * k }

    private var photosWidth: CGFloat {
        let count = CGFloat(metrics.thumbnailsPerRow)
        return metrics.thumbnail * count + thumbnailGap * (count - 1) + 12 * k
    }
    private var workWidth: CGFloat { width - metrics.dayWidth - photosWidth }
    /// The code column's width, nothing when no item has a code.
    private var codeWidth: CGFloat { document.showsCodes ? metrics.codeWidth : 0 }
    private var materialNameWidth: CGFloat { width - codeWidth - metrics.quantityWidth - metrics.unitWidth }

    // MARK: - Type

    private func scaled(_ font: UIFont) -> UIFont {
        k == 1 ? font : font.withSize(font.pointSize * k)
    }

    private var cellFont: UIFont { scaled(PDFReportStyle.cellFont) }
    private var cellBoldFont: UIFont { scaled(PDFReportStyle.cellBoldFont) }
    private var headingFont: UIFont { scaled(PDFReportStyle.headingFont) }
    private var eyebrowFont: UIFont { scaled(PDFReportStyle.eyebrowFont) }
    private var titleFont: UIFont { scaled(PDFReportStyle.titleFont) }
    private var bylineFont: UIFont { scaled(PDFReportStyle.bylineFont) }
    private var addressFont: UIFont { scaled(PDFReportStyle.addressFont) }
    private var figureLabelFont: UIFont { scaled(PDFReportStyle.figureLabelFont) }
    private var figureValueFont: UIFont { scaled(PDFReportStyle.figureValueFont) }
    private var smallFont: UIFont { scaled(PDFReportStyle.smallFont) }
    private var footerFont: UIFont { scaled(PDFReportStyle.footerFont) }

    // MARK: - Blocks

    /// The work done first, what is still in progress after it, the
    /// material last.
    var blocks: [Block] {
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
        return blocks
    }

    func height(of block: Block) -> CGFloat {
        switch block {
        case .header: return headerHeight
        case .jobsHead, .progressHead, .materialHead: return sectionGap + sectionTitleHeight + columnHeadHeight
        case .material: return materialRowHeight
        case let .job(index): return jobHeight(document.jobs[index])
        case let .progressJob(index): return jobHeight(document.inProgressJobs[index])
        }
    }

    // MARK: - Measuring

    private func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(bounds.height)
    }

    /// What the job's cell says, top to bottom: what was done, then each
    /// item on a line of its own ("4 × P7" over "2 × P6"), then how long it
    /// took and who, then who confirmed it. Each is measured on its own, so
    /// a job of many items is as tall as it prints.
    private func textLines(of job: ExtraWorkDocument.JobRow) -> [(String, UIFont, UIColor)] {
        var lines: [(String, UIFont, UIColor)] = [(job.description, cellBoldFont, PDFReportStyle.ink)]
        for item in job.materialLines {
            lines.append((item, cellFont, PDFReportStyle.ink))
        }
        lines.append((job.hours, cellFont, PDFReportStyle.secondary))
        lines.append((job.confirmation, smallFont, PDFReportStyle.secondary))
        return lines.filter { !$0.0.isEmpty }
    }

    private func photoRows(_ job: ExtraWorkDocument.JobRow) -> Int {
        let count = job.photoIDs.filter { images[$0] != nil }.count
        let perRow = max(1, metrics.thumbnailsPerRow)
        return (count + perRow - 1) / perRow
    }

    private func jobHeight(_ job: ExtraWorkDocument.JobRow) -> CGFloat {
        let inner = workWidth - cellPadding * 2
        var text = textLines(of: job).reduce(CGFloat(0)) { $0 + textHeight($1.0, font: $1.1, width: inner) + 2 * k }
        if job.signature != nil { text += jobSignatureHeight }
        let rows = photoRows(job)
        let photos = rows == 0 ? 0 : CGFloat(rows) * metrics.thumbnail + CGFloat(rows - 1) * thumbnailGap
        return max(text, photos, cellFont.lineHeight) + rowPadding * 2
    }

    /// The two figures at the top right, as plain text (polish, 2026-11):
    /// "Jobs done  4" over "In progress  1".
    private var figures: [ReportTile] { Array(document.tiles.prefix(2)) }

    private var figureGap: CGFloat { 6 * k }
    private var figureLineHeight: CGFloat { 14 * k }
    /// Where the first figure is, from the header's top: level with the
    /// byline, under the title's line.
    private var figuresTop: CGFloat { 40 * k }

    private var figuresWidth: CGFloat {
        figures.map { figure in
            ceil(PDFReportStyle.width(of: figure.label, font: figureLabelFont)
                + figureGap
                + PDFReportStyle.width(of: figure.value, font: figureValueFont))
        }.max() ?? 0
    }

    /// What is left beside the figures for the lines under the title.
    private var titleWidth: CGFloat {
        width - figuresWidth - (figures.isEmpty ? 0 : 16 * k)
    }

    private var headerHeight: CGFloat {
        headerBase + addressExtra
    }

    /// The site's address goes under the byline, one smaller line, as on the
    /// site sheet. It sits in the byline's two-line slot when there is room,
    /// and pushes the rest of the header down only by what it needs.
    private var addressTop: CGFloat {
        guard !document.byline.isEmpty else { return 43 * k }
        let byline = min(24 * k, textHeight(document.byline, font: bylineFont, width: titleWidth))
        return 43 * k + byline + 1 * k
    }

    private var addressLineHeight: CGFloat { 11 * k }

    private var addressExtra: CGFloat {
        guard !document.address.isEmpty else { return 0 }
        return max(0, addressTop + addressLineHeight - 67 * k)
    }

    // MARK: - Drawing

    /// Draws `block` with its top at `y`, returning where the next begins.
    @discardableResult
    func draw(_ block: Block, at y: CGFloat) -> CGFloat {
        switch block {
        case .header:
            drawHeader(at: y)
        case .jobsHead, .progressHead:
            drawSection(
                block == .jobsHead ? document.jobsHeading : document.inProgressHeading,
                columns: [(document.jobHeadings[0], metrics.dayWidth, .left),
                          (document.jobHeadings[1], workWidth, .left),
                          (document.jobHeadings[2], photosWidth, .left)],
                at: y
            )
        case let .job(index):
            drawJob(document.jobs[index], isLast: index == document.jobs.count - 1, at: y)
        case let .progressJob(index):
            drawJob(document.inProgressJobs[index], isLast: index == document.inProgressJobs.count - 1, at: y)
        case .materialHead:
            drawSection(document.materialHeading, columns: materialColumns, at: y)
        case let .material(index):
            drawMaterial(document.material[index], isLast: index == document.material.count - 1, at: y)
        }
        return y + height(of: block)
    }

    /// "EXTRA WORK DONE · 19 – 22 OCTOBER 2026" in small orange capitals,
    /// the site's name in bold under it, who recorded it and the address in
    /// grey, and the figures as plain text on the right (no tiles).
    private func drawHeader(at y: CGFloat) {
        PDFReportStyle.draw(
            document.eyebrow.uppercased(with: document.language.locale),
            in: CGRect(x: margin, y: y, width: width, height: 11 * k),
            font: eyebrowFont,
            color: PDFReportStyle.accent,
            kern: 0.8 * k
        )
        // The full width: a long site name is the one word the boss files
        // the sheet by.
        PDFReportStyle.draw(
            document.title,
            in: CGRect(x: margin, y: y + 12 * k, width: width, height: 30 * k),
            font: titleFont,
            color: PDFReportStyle.ink
        )
        PDFReportStyle.drawWrapping(
            document.byline,
            in: CGRect(x: margin, y: y + 43 * k, width: titleWidth, height: 24 * k),
            font: bylineFont,
            color: PDFReportStyle.secondary
        )

        if !document.address.isEmpty {
            // Beside the figures it keeps clear of them; below them it has
            // the width.
            let besideFigures = addressTop < figuresTop + CGFloat(figures.count) * figureLineHeight
            PDFReportStyle.draw(
                document.address,
                in: CGRect(x: margin, y: y + addressTop, width: besideFigures ? titleWidth : width, height: addressLineHeight),
                font: addressFont,
                color: PDFReportStyle.secondary
            )
        }

        // Right-aligned beside the grey lines under the title.
        let figuresX = margin + width - figuresWidth
        for (index, figure) in figures.enumerated() {
            let top = y + figuresTop + CGFloat(index) * figureLineHeight
            let valueWidth = ceil(PDFReportStyle.width(of: figure.value, font: figureValueFont)) + 1
            PDFReportStyle.draw(figure.value, in: CGRect(x: margin + width - valueWidth, y: top, width: valueWidth, height: figureLineHeight),
                                font: figureValueFont, color: PDFReportStyle.ink, alignment: .right)
            PDFReportStyle.draw(figure.label, in: CGRect(x: figuresX, y: top, width: max(0, figuresWidth - valueWidth - figureGap), height: figureLineHeight),
                                font: figureLabelFont, color: PDFReportStyle.secondary, alignment: .right)
        }

        let ruleY = y + headerHeight - 6 * k
        PDFReportStyle.line(from: CGPoint(x: margin, y: ruleY), to: CGPoint(x: margin + width, y: ruleY),
                            width: 1 * k, color: PDFReportStyle.ink)
    }

    /// "WORK DONE, DAY BY DAY", then the column heads over a thin dark rule.
    private func drawSection(_ title: String, columns: [(String, CGFloat, NSTextAlignment)], at start: CGFloat) {
        let locale = document.language.locale
        var y = start + sectionGap
        PDFReportStyle.draw(title.uppercased(with: locale), in: CGRect(x: margin, y: y, width: width, height: sectionTitleHeight),
                            font: headingFont, color: PDFReportStyle.secondary, kern: 0.3 * k)
        y += sectionTitleHeight
        var x = margin
        for (heading, columnWidth, alignment) in columns {
            PDFReportStyle.draw(heading.uppercased(with: locale),
                                in: CGRect(x: x + cellPadding, y: y, width: columnWidth - cellPadding * 2, height: columnHeadHeight),
                                font: headingFont, color: PDFReportStyle.secondary, alignment: alignment, kern: 0.3 * k)
            x += columnWidth
        }
        PDFReportStyle.line(from: CGPoint(x: margin, y: y + columnHeadHeight), to: CGPoint(x: margin + width, y: y + columnHeadHeight),
                            width: 0.8 * k, color: PDFReportStyle.ink)
    }

    private func rowRule(at y: CGFloat, isLast: Bool) {
        PDFReportStyle.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y),
                            width: (isLast ? 1.2 : 0.5) * k, color: isLast ? PDFReportStyle.ink : PDFReportStyle.rule)
    }

    /// Item, then its code when any item has one, then quantity and unit:
    /// the headings come from the document, which has the code's only when
    /// the column is there.
    private var materialColumns: [(String, CGFloat, NSTextAlignment)] {
        let headings = document.materialHeadings
        guard headings.count >= 3 else { return [] }
        if document.showsCodes, headings.count >= 4 {
            return [(headings[0], materialNameWidth, .left),
                    (headings[1], codeWidth, .left),
                    (headings[2], metrics.quantityWidth, .right),
                    (headings[3], metrics.unitWidth, .left)]
        }
        return [(headings[0], materialNameWidth, .left),
                (headings[1], metrics.quantityWidth, .right),
                (headings[2], metrics.unitWidth, .left)]
    }

    private func drawMaterial(_ line: ExtraWorkDocument.MaterialRow, isLast: Bool, at y: CGFloat) {
        let padding = cellPadding
        let quantityWidth = metrics.quantityWidth
        let unitWidth = metrics.unitWidth
        let nameWidth = materialNameWidth
        let codeWidth = self.codeWidth
        PDFReportStyle.draw(line.name, in: CGRect(x: margin + padding, y: y, width: nameWidth - padding * 2, height: materialRowHeight),
                            font: cellFont, color: PDFReportStyle.ink)
        if codeWidth > 0, !line.code.isEmpty {
            // The cell font has monospaced digits, so codes line up.
            PDFReportStyle.draw(line.code, in: CGRect(x: margin + nameWidth + padding, y: y, width: codeWidth - padding * 2, height: materialRowHeight),
                                font: cellFont, color: PDFReportStyle.secondary)
        }
        let quantityX = margin + nameWidth + codeWidth
        PDFReportStyle.draw(line.quantity, in: CGRect(x: quantityX + padding, y: y, width: quantityWidth - padding * 2, height: materialRowHeight),
                            font: cellBoldFont, color: PDFReportStyle.ink, alignment: .right)
        PDFReportStyle.draw(line.unit, in: CGRect(x: quantityX + quantityWidth + padding, y: y, width: unitWidth - padding * 2, height: materialRowHeight),
                            font: cellFont, color: PDFReportStyle.secondary)
        rowRule(at: y + materialRowHeight, isLast: isLast)
    }

    private func drawJob(_ job: ExtraWorkDocument.JobRow, isLast: Bool, at start: CGFloat) {
        let rowHeight = jobHeight(job)
        let padding = cellPadding
        let y = start + rowPadding
        let dayWidth = metrics.dayWidth

        PDFReportStyle.draw(job.day, in: CGRect(x: margin + padding, y: y, width: dayWidth - padding * 2, height: 12 * k),
                            font: cellBoldFont, color: PDFReportStyle.ink)

        let workX = margin + dayWidth + padding
        let inner = workWidth - padding * 2
        var textY = y
        for (text, font, color) in textLines(of: job) {
            let height = textHeight(text, font: font, width: inner)
            PDFReportStyle.drawWrapping(text, in: CGRect(x: workX, y: textY, width: inner, height: height + 2 * k), font: font, color: color)
            textY += height + 2 * k
        }
        if let signature = job.signature {
            let area = CGRect(x: workX, y: textY, width: metrics.jobSignatureWidth, height: jobSignatureHeight - 2 * k)
            PDFAppendix.drawStrokes(signature.strokes, aspectRatio: signature.aspectRatio, in: area)
        }

        let photosX = margin + dayWidth + workWidth + padding
        let shown = job.photoIDs.compactMap { images[$0] }
        let thumbnail = metrics.thumbnail
        let perRow = max(1, metrics.thumbnailsPerRow)
        if shown.isEmpty {
            PDFReportStyle.draw("—", in: CGRect(x: photosX, y: y, width: 20 * k, height: 12 * k),
                                font: cellFont, color: PDFReportStyle.faint)
        } else {
            for (index, image) in shown.enumerated() {
                let cell = CGRect(
                    x: photosX + CGFloat(index % perRow) * (thumbnail + thumbnailGap),
                    y: y + CGFloat(index / perRow) * (thumbnail + thumbnailGap),
                    width: thumbnail,
                    height: thumbnail
                )
                drawFilled(image, in: cell)
            }
        }

        rowRule(at: start + rowHeight, isLast: isLast)
    }

    /// A photo cropped to fill its square, with rounded corners.
    private func drawFilled(_ image: UIImage, in cell: CGRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(cell.width / image.size.width, cell.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let frame = CGRect(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2, width: size.width, height: size.height)
        UIGraphicsGetCurrentContext()?.saveGState()
        UIBezierPath(roundedRect: cell, cornerRadius: 3 * k).addClip()
        image.draw(in: frame)
        UIGraphicsGetCurrentContext()?.restoreGState()
    }

    /// The legend on the left; on the right, the client's signature under
    /// the whole report with "Confirmed on site by …", when they gave one.
    /// No empty lines: this is a report, not a form.
    ///
    /// - Parameter bottom: the lowest the closing may reach, just above the
    ///   footer line.
    func drawClosing(above bottom: CGFloat) {
        let lineY = bottom - 14 * k
        let areaTop = lineY - closingHeight + 20 * k
        let signatureWidth = metrics.signatureWidth
        let gap = 18 * k
        let legendWidth = document.clientSignature == nil ? width : width - signatureWidth - gap

        PDFReportStyle.drawWrapping(document.legend, in: CGRect(x: margin, y: lineY - 34 * k, width: max(120 * k, legendWidth), height: 46 * k),
                                    font: smallFont, color: PDFReportStyle.secondary)

        if let signature = document.clientSignature {
            let x = margin + legendWidth + gap
            let area = CGRect(x: x, y: areaTop, width: signatureWidth, height: lineY - areaTop - 2 * k)
            PDFAppendix.drawStrokes(signature.strokes, aspectRatio: signature.aspectRatio, in: area)
            PDFReportStyle.line(from: CGPoint(x: x, y: lineY), to: CGPoint(x: x + signatureWidth, y: lineY),
                                width: 0.6 * k, color: PDFReportStyle.signatureRule)
            // One line, above the page count: 7.5 pt fits "Confirmed on site
            // by" a long name and a date in this width.
            PDFReportStyle.draw(document.clientSignatureLabel, in: CGRect(x: x, y: lineY + 1 * k, width: signatureWidth, height: 11 * k),
                                font: smallFont, color: PDFReportStyle.secondary)
        }
    }

    /// "Zeitkonto · page 1 of 2" on a page, "Zeitkonto" alone on the
    /// picture, right-aligned in the footer line under `closingBottom`.
    func drawFooter(_ text: String, below closingBottom: CGFloat) {
        PDFReportStyle.draw(text, in: CGRect(x: margin, y: closingBottom + footerLine - 10 * k, width: width, height: 10 * k),
                            font: footerFont, color: PDFReportStyle.faint, alignment: .right)
    }
}
