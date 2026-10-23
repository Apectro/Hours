import XCTest
import UIKit
@testable import Hours

/// The report as one tall picture for a chat. A picture has no text to read
/// back, so these check its shape: one image, the width a phone shows full
/// screen, as tall as the report and growing with it, never cut into pages.
final class ExtraWorkPictureTests: XCTestCase {
    private let site = Site(name: "Trg Pravde Zagreb")
    private let calendar = Fixture.calendar()

    private func document(jobs count: Int, items: Int = 2, signed: Bool = false, inProgress: Bool = false) -> ExtraWorkDocument {
        let settings = Fixture.settings(export: ExportPreferences(language: .german, ownerName: "Marijo Mikša"))
        let jobs = (0..<count).map { index in
            ExtraWorkJob(
                siteID: site.id,
                date: Fixture.date(2026, 10, 1 + index % 28),
                description: "Notbeleuchtung \(index)",
                items: (1...items).map { ExtraWorkItem(name: "P\($0)", quantity: Decimal($0), unit: .pieces) },
                hours: [ExtraWorkHours(name: "Marijo Mikša", minutes: 60)],
                isDone: !(inProgress && index == count - 1)
            )
        }
        let signature = signed
            ? ExtraWorkSignature(signerName: "Ing. M. Horvat", signedAt: Date(timeIntervalSince1970: 1_792_000_000),
                                 strokes: [[SignaturePoint(x: 0.1, y: 0.5), SignaturePoint(x: 2.5, y: 0.3)]])
            : nil
        return ExtraWorkDocumentBuilder(settings: settings, calendar: calendar)
            .make(report: ExtraWorkReport(siteID: site.id, jobs: jobs, clientSignature: signature), siteName: site.name)
    }

    func testThePictureIsOneImageTheWidthOfAPhoneScreen() throws {
        let picture = ExtraWorkPictureRenderer.picture(for: document(jobs: 3))
        XCTAssertFalse(picture.data.isEmpty)
        XCTAssertTrue(["png", "jpg"].contains(picture.fileExtension))
        let image = try XCTUnwrap(UIImage(data: picture.data), "the bytes decode as one image")
        XCTAssertNil(image.images, "a still, not an animation of pages")
        XCTAssertEqual(image.size.width * image.scale, 1080, accuracy: 1)
        XCTAssertEqual(picture.size.width, 1080, accuracy: 1)
        XCTAssertGreaterThan(picture.size.height, picture.size.width / 2, "a header, three jobs and the material")
    }

    /// No pages: more jobs make the one picture taller.
    func testThePictureGrowsWithTheJobs() {
        let three = ExtraWorkPictureRenderer.image(for: document(jobs: 3)).size.height
        let ten = ExtraWorkPictureRenderer.image(for: document(jobs: 10)).size.height
        let tenOfSixItems = ExtraWorkPictureRenderer.image(for: document(jobs: 10, items: 6)).size.height
        XCTAssertGreaterThan(ten, three)
        XCTAssertGreaterThan(tenOfSixItems, ten, "every item on a line of its own")
    }

    /// Sixty jobs run over several A4 pages; the picture stays one image.
    func testALongReportIsStillOnePicture() throws {
        let document = document(jobs: 60)
        let picture = ExtraWorkPictureRenderer.picture(for: document)
        XCTAssertNotNil(UIImage(data: picture.data))
        XCTAssertGreaterThan(picture.size.height, ExtraWorkPictureRenderer.metrics.pageWidth * 3)
    }

    /// The in-progress section and a signature are drawn when there are
    /// some, and take room.
    func testInProgressAndASignatureTakeRoom() {
        let plain = ExtraWorkPictureRenderer.image(for: document(jobs: 3)).size.height
        let withProgress = ExtraWorkPictureRenderer.image(for: document(jobs: 3, inProgress: true)).size.height
        XCTAssertGreaterThan(withProgress, plain, "a heading of its own for the job still in progress")
        let signed = ExtraWorkPictureRenderer.image(for: document(jobs: 3, signed: true)).size.height
        XCTAssertEqual(signed, plain, accuracy: 1, "the signature sits in the closing, beside the legend")
    }

    /// The table's text is large enough to read in a chat without zooming.
    func testTheTextIsPhoneSized() {
        let metrics = ExtraWorkPictureRenderer.metrics
        XCTAssertGreaterThanOrEqual(PDFReportStyle.cellFont.pointSize * metrics.scale, 28)
        XCTAssertEqual(metrics.pageWidth, 1080)
    }

    /// The PDF is drawn from the same layout and is still A4.
    func testThePDFIsStillA4() {
        XCTAssertEqual(ExtraWorkReportLayout.Metrics.pdf.pageWidth, ExtraWorkPDFRenderer.pageSize.width)
        XCTAssertEqual(ExtraWorkReportLayout.Metrics.pdf.scale, 1)
    }
}
