import UIKit

/// The printed page's measurements, type and colours, in one place.
///
/// The colours are fixed values rather than the system's dynamic ones. A PDF
/// is paper: drawn with `.label` it came out in whatever the phone's
/// appearance happened to be when the file was written, and a timesheet
/// exported at night is not meant to be white on black.
enum PDFReportStyle {
    /// A4 landscape. Wide enough for ten columns without squeezing.
    static let pageSize = CGSize(width: 842, height: 595)

    /// Left and right. Visible to the tests, which measure the columns
    /// against the width this leaves.
    static let margin: CGFloat = 32
    static let topMargin: CGFloat = 28
    static let bottomMargin: CGFloat = 18
    /// The strip at the foot of every page: the page count, and on the last
    /// page the legend and the lines to sign on.
    static let footerBand: CGFloat = 36

    static let rowHeight: CGFloat = 14
    /// Totals and counts stand a little taller than the days above them.
    static let closingRowHeight: CGFloat = 18
    static let headingHeight: CGFloat = 18
    static let cellPadding: CGFloat = 5

    static var contentWidth: CGFloat { pageSize.width - margin * 2 }
    /// The lowest a row may reach before the page is full.
    static var contentBottom: CGFloat { pageSize.height - bottomMargin - footerBand }

    // MARK: - Type

    /// Tabular figures throughout the table, so a column of hours lines up
    /// digit under digit.
    static let cellFont = UIFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
    static let cellBoldFont = UIFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
    static let headingFont = UIFont.systemFont(ofSize: 7, weight: .bold)
    static let eyebrowFont = UIFont.systemFont(ofSize: 8, weight: .bold)
    static let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
    static let bylineFont = UIFont.systemFont(ofSize: 9.5)
    /// A site's address under the byline: the byline's look, a size down.
    static let addressFont = UIFont.systemFont(ofSize: 8.5)
    static let tileLabelFont = UIFont.systemFont(ofSize: 7.5)
    static let tileValueFont = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .bold)
    static let smallFont = UIFont.systemFont(ofSize: 7.5)
    static let footerFont = UIFont.systemFont(ofSize: 7)

    // MARK: - Colours

    static let ink = rgb(0x1C1C1E)
    static let secondary = rgb(0x636366)
    static let faint = rgb(0xAEAEB2)
    static let rule = rgb(0xECECF0)
    static let signatureRule = rgb(0x8E8E93)
    /// The eyebrow, and someone who came late or left early.
    static let accent = rgb(0xE07B12)
    static let tile = rgb(0xF2F2F7)
    static let negativeTile = rgb(0xFDECEA)
    static let negative = rgb(0xC62828)
    static let positive = rgb(0x2E7D32)
    /// A day nobody expected anything of.
    static let restWash = rgb(0xF6F6F8)
    /// A day of paid absence.
    static let absenceWash = rgb(0xFFF7EC)
    /// A day worked on more than one site: its rows, one shade as one group.
    static let splitDayWash = rgb(0xF6F8FC)

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    // MARK: - Measuring and drawing text

    static func width(of text: String, font: UIFont, kern: CGFloat = 0) -> CGFloat {
        (text as NSString).size(withAttributes: textAttributes(font: font, color: ink, kern: kern)).width
    }

    /// Draws one line, cut short with an ellipsis if it does not fit, centred
    /// vertically in `rect`.
    static func draw(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment = .left,
        kern: CGFloat = 0
    ) {
        guard !text.isEmpty, rect.width > 0 else { return }
        var attributes = textAttributes(font: font, color: color, kern: kern)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        attributes[.paragraphStyle] = paragraph
        let lineHeight = font.lineHeight
        let line = CGRect(
            x: rect.minX,
            y: rect.minY + max(0, (rect.height - lineHeight) / 2),
            width: rect.width,
            height: lineHeight
        )
        NSAttributedString(string: text, attributes: attributes).draw(in: line)
    }

    /// Draws text that may wrap onto several lines, from the top of `rect`.
    static func drawWrapping(_ text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        guard !text.isEmpty, rect.width > 0 else { return }
        var attributes = textAttributes(font: font, color: color, kern: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        attributes[.paragraphStyle] = paragraph
        NSAttributedString(string: text, attributes: attributes).draw(in: rect)
    }

    static func line(from start: CGPoint, to end: CGPoint, width: CGFloat, color: UIColor) {
        color.setStroke()
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        path.lineWidth = width
        path.stroke()
    }

    private static func textAttributes(font: UIFont, color: UIColor, kern: CGFloat) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if kern != 0 { attributes[.kern] = kern }
        return attributes
    }
}
