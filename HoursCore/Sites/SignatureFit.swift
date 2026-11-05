import Foundation

/// A signature drawn on the full-screen pad (1.3), made to fit the box every
/// signature has always been stored in.
///
/// The pad is as wide as the screen: on a phone in landscape about 2.2 units
/// wide for one high, on an iPad whatever shape it is held in. The sheets
/// print a signature from a 3:1 box (`CrewSignature.aspectRatio`,
/// `ExtraWorkSignature.aspectRatio`), so the drawing is cropped to its ink
/// and scaled, the same amount both ways, until it touches the box's sides or
/// its top and bottom, less a small margin. It sits at the box's leading edge,
/// centred on its middle line. Nothing is stretched.
enum SignatureFit {
    /// Width over height of the stored box, as before the pad went full screen.
    static let boxAspectRatio: Double = 3
    /// Space kept clear round the ink, in box heights.
    static let margin: Double = 0.06

    /// - Parameters:
    ///   - strokes: points in a box one unit high, as the pad records them.
    ///   - drawnIn: the pad's width over its height. Only bounds the input;
    ///     the ink decides the crop.
    static func fit(_ strokes: [[SignaturePoint]], drawnIn aspectRatio: Double) -> [[SignaturePoint]] {
        let kept = strokes.filter { !$0.isEmpty }
        let points = kept.flatMap { $0 }
        guard let first = points.first else { return [] }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        let width = maxX - minX
        let height = maxY - minY
        let roomX = boxAspectRatio - 2 * margin
        let roomY = 1 - 2 * margin
        let tiny = 1e-6

        let scale: Double
        switch (width > tiny, height > tiny) {
        case (true, true): scale = min(roomX / width, roomY / height)
        case (true, false): scale = roomX / width
        case (false, true): scale = roomY / height
        case (false, false): scale = 1
        }
        let offsetY = 0.5 - (height * scale) / 2
        return kept.map { stroke in
            stroke.map { point in
                SignaturePoint(
                    x: clamp(margin + (point.x - minX) * scale, upTo: boxAspectRatio),
                    y: clamp(offsetY + (point.y - minY) * scale, upTo: 1)
                )
            }
        }
    }

    /// A touch on the pad, in pad points, as a point in the pad's own box one
    /// unit high, kept inside the pad.
    static func point(x: Double, y: Double, padWidth: Double, padHeight: Double) -> SignaturePoint {
        let height = max(padHeight, 1)
        let width = max(padWidth, 1)
        return SignaturePoint(
            x: min(max(x, 0), width) / height,
            y: min(max(y, 0), height) / height
        )
    }

    private static func clamp(_ value: Double, upTo limit: Double) -> Double {
        min(max(value, 0), limit)
    }
}

/// Which way the interface faces while someone signs, and afterwards.
///
/// A phone turns to landscape for a longer line to write on, and back to
/// portrait when it was held that way before. An iPad is big enough either
/// way and is never turned.
enum SigningOrientation: Equatable, Sendable {
    case portrait
    case landscape

    struct Plan: Equatable, Sendable {
        /// What the interface is locked to while the pad is open; nil leaves
        /// it free.
        var whileSigning: SigningOrientation?
        /// What it is turned back to when the pad closes; nil leaves it as is.
        var afterwards: SigningOrientation?
    }

    static func plan(isPad: Bool, wasPortrait: Bool) -> Plan {
        guard !isPad else { return Plan(whileSigning: nil, afterwards: nil) }
        return Plan(whileSigning: .landscape, afterwards: wasPortrait ? .portrait : nil)
    }
}
