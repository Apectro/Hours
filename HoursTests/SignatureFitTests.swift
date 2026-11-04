import XCTest
@testable import Hours

/// Signing full screen (1.3): a signature drawn on a landscape pad, or on an
/// iPad in any shape, is stored in the same 3:1 box as before, cropped to the
/// ink and scaled without distortion, so the sheets print it as they always
/// have.
final class SignatureFitTests: XCTestCase {
    private func p(_ x: Double, _ y: Double) -> SignaturePoint { SignaturePoint(x: x, y: y) }

    private func bounds(_ strokes: [[SignaturePoint]]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let points = strokes.flatMap { $0 }
        return (points.map(\.x).min()!, points.map(\.y).min()!, points.map(\.x).max()!, points.map(\.y).max()!)
    }

    func testTheStoredBoxIsTheOneTheSheetsAlwaysUsed() {
        XCTAssertEqual(SignatureFit.boxAspectRatio, 3)
    }

    func testNothingDrawnStaysNothing() {
        XCTAssertEqual(SignatureFit.fit([], drawnIn: 2.2), [])
        XCTAssertEqual(SignatureFit.fit([[]], drawnIn: 2.2), [])
    }

    func testAWideSignatureFillsTheWidthAndKeepsItsProportions() {
        // Drawn across a landscape pad 2.2 units wide: 1.8 wide, 0.3 high.
        let drawn = [[p(0.2, 0.5), p(1.0, 0.35), p(2.0, 0.65)]]
        let fitted = SignatureFit.fit(drawn, drawnIn: 2.2)
        let b = bounds(fitted)
        let margin = SignatureFit.margin
        XCTAssertEqual(b.minX, margin, accuracy: 1e-9)
        XCTAssertEqual(b.maxX, 3 - margin, accuracy: 1e-9)
        // Same shape: width over height unchanged.
        XCTAssertEqual((b.maxX - b.minX) / (b.maxY - b.minY), 1.8 / 0.3, accuracy: 1e-9)
        // Centred on the box's middle line.
        XCTAssertEqual((b.minY + b.maxY) / 2, 0.5, accuracy: 1e-9)
    }

    func testATallSignatureFillsTheHeightAndStartsAtTheLeadingEdge() {
        // A tall scrawl on an iPad held upright: 0.4 wide, 0.8 high.
        let drawn = [[p(0.3, 0.1), p(0.5, 0.9)], [p(0.6, 0.2), p(0.7, 0.5)]]
        let fitted = SignatureFit.fit(drawn, drawnIn: 0.75)
        let b = bounds(fitted)
        let margin = SignatureFit.margin
        XCTAssertEqual(b.minY, margin, accuracy: 1e-9)
        XCTAssertEqual(b.maxY, 1 - margin, accuracy: 1e-9)
        XCTAssertEqual(b.minX, margin, accuracy: 1e-9)
        XCTAssertEqual((b.maxX - b.minX) / (b.maxY - b.minY), 0.4 / 0.8, accuracy: 1e-9)
    }

    func testEveryPointLandsInsideTheBox() {
        let drawn = [[p(0, 0), p(2.4, 1)], [p(1.2, 0.5), p(1.3, 0.55)]]
        for stroke in SignatureFit.fit(drawn, drawnIn: 2.4) {
            for point in stroke {
                XCTAssertGreaterThanOrEqual(point.x, 0)
                XCTAssertLessThanOrEqual(point.x, SignatureFit.boxAspectRatio)
                XCTAssertGreaterThanOrEqual(point.y, 0)
                XCTAssertLessThanOrEqual(point.y, 1)
            }
        }
    }

    func testStrokesAndPointsAreKeptInOrder() {
        let drawn = [[p(0.2, 0.5), p(0.4, 0.6)], [p(1.0, 0.3)], [p(1.5, 0.4), p(1.6, 0.5), p(1.7, 0.4)]]
        let fitted = SignatureFit.fit(drawn, drawnIn: 2)
        XCTAssertEqual(fitted.map(\.count), [2, 1, 3])
        XCTAssertLessThan(fitted[0][0].x, fitted[0][1].x)
        XCTAssertLessThan(fitted[1][0].x, fitted[2][0].x)
    }

    func testAStraightLineDoesNotDivideByZero() {
        let fitted = SignatureFit.fit([[p(0.5, 0.5), p(1.5, 0.5)]], drawnIn: 2)
        let b = bounds(fitted)
        XCTAssertFalse(fitted.flatMap { $0 }.contains { $0.x.isNaN || $0.y.isNaN })
        XCTAssertEqual(b.minY, 0.5, accuracy: 1e-9)
        XCTAssertEqual(b.maxX - b.minX, 3 - 2 * SignatureFit.margin, accuracy: 1e-9)
    }

    func testASingleDotStaysADotAndIsNotASignature() {
        let fitted = SignatureFit.fit([[p(1, 0.5)]], drawnIn: 2)
        XCTAssertEqual(fitted.count, 1)
        XCTAssertFalse(fitted[0][0].x.isNaN)
        XCTAssertFalse(CrewSignature.isSignature(fitted))
    }

    func testASignatureStaysASignature() {
        let drawn = [[p(0.2, 0.5), p(0.5, 0.45), p(0.9, 0.55)]]
        XCTAssertTrue(CrewSignature.isSignature(drawn))
        XCTAssertTrue(CrewSignature.isSignature(SignatureFit.fit(drawn, drawnIn: 2.1)))
    }

    func testCanvasPointsAreClampedToThePad() {
        let point = SignatureFit.point(x: 900, y: -20, padWidth: 800, padHeight: 300)
        XCTAssertEqual(point.x, 800.0 / 300.0, accuracy: 1e-9)
        XCTAssertEqual(point.y, 0)
        let inside = SignatureFit.point(x: 150, y: 150, padWidth: 800, padHeight: 300)
        XCTAssertEqual(inside.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(inside.y, 0.5, accuracy: 1e-9)
    }

    // MARK: - Orientation

    func testAPhoneSignsInLandscapeAndGoesBackToPortrait() {
        let plan = SigningOrientation.plan(isPad: false, wasPortrait: true)
        XCTAssertEqual(plan.whileSigning, .landscape)
        XCTAssertEqual(plan.afterwards, .portrait)
    }

    func testAPhoneAlreadyInLandscapeStaysThere() {
        let plan = SigningOrientation.plan(isPad: false, wasPortrait: false)
        XCTAssertEqual(plan.whileSigning, .landscape)
        XCTAssertNil(plan.afterwards)
    }

    func testAnIPadIsNeverTurned() {
        let plan = SigningOrientation.plan(isPad: true, wasPortrait: true)
        XCTAssertNil(plan.whileSigning)
        XCTAssertNil(plan.afterwards)
    }
}
