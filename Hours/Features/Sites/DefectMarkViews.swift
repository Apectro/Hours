import SwiftUI
import UIKit

/// The marks over a defect's photo, drawn the same way everywhere: on the
/// marking screen, the list's thumbnails, the viewer and the PDF. Each
/// mark is a path over the rectangle the photo is drawn in, from its
/// normalised points (`DefectGeometry`); the photo itself is never changed.
enum DefectMarkPainter {
    static func uiColor(_ colour: DefectMark.Colour) -> UIColor {
        switch colour {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .white: return .white
        }
    }

    static func color(_ colour: DefectMark.Colour) -> Color {
        Color(uiColor: uiColor(colour))
    }

    /// One mark's path over a photo drawn in `rect`.
    static func path(for mark: DefectMark, in rect: CGRect) -> CGPath {
        let drawn = DefectRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        let path = CGMutablePath()
        switch mark.kind {
        case .circle:
            guard let box = mark.box else { return path }
            let onPhoto = DefectGeometry.absolute(box, in: drawn)
            path.addEllipse(in: CGRect(x: onPhoto.x, y: onPhoto.y, width: onPhoto.width, height: onPhoto.height))
        case .arrow:
            guard let first = mark.points.first, let last = mark.points.last else { return path }
            let tail = DefectGeometry.absolute(first, in: drawn)
            let tip = DefectGeometry.absolute(last, in: drawn)
            path.move(to: CGPoint(x: tail.x, y: tail.y))
            path.addLine(to: CGPoint(x: tip.x, y: tip.y))
            for wing in DefectGeometry.arrowHead(tail: tail, tip: tip, length: DefectGeometry.arrowHeadLength(in: drawn)) {
                path.move(to: CGPoint(x: tip.x, y: tip.y))
                path.addLine(to: CGPoint(x: wing.x, y: wing.y))
            }
        case .draw:
            let points = mark.points.map { DefectGeometry.absolute($0, in: drawn) }
            guard let first = points.first else { return path }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for point in points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
        }
        return path
    }

    static func lineWidth(in rect: CGRect) -> CGFloat {
        CGFloat(DefectGeometry.lineWidth(in: DefectRect(x: 0, y: 0, width: rect.width, height: rect.height)))
    }

    /// The marks into the current graphics context (the PDF's), with a thin
    /// dark edge so a white or yellow mark still shows on a pale wall.
    static func draw(_ marks: [DefectMark], in rect: CGRect, context: CGContext) {
        let width = lineWidth(in: rect)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for mark in marks {
            let path = path(for: mark, in: rect)
            context.addPath(path)
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(width + 1.5)
            context.strokePath()
            context.addPath(path)
            context.setStrokeColor(uiColor(mark.colour).cgColor)
            context.setLineWidth(width)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// Where a photo of `size` is drawn to fill `container`, cropped: the
    /// thumbnails' square.
    static func filled(_ size: CGSize, in container: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return container }
        let scale = max(container.width / size.width, container.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(x: container.midX - width / 2, y: container.midY - height / 2, width: width, height: height)
    }

    /// Where a photo of `size` is drawn to fit `container`, whole.
    static func fitted(_ size: CGSize, in container: CGRect) -> CGRect {
        let fitted = DefectGeometry.fitted(
            imageWidth: size.width,
            imageHeight: size.height,
            in: DefectRect(x: container.minX, y: container.minY, width: container.width, height: container.height)
        )
        return CGRect(x: fitted.x, y: fitted.y, width: fitted.width, height: fitted.height)
    }
}

/// Marks drawn over a photo of `imageSize` that fills or fits the view.
struct DefectMarksOverlay: View {
    let marks: [DefectMark]
    let imageSize: CGSize
    var fills = false
    /// A mark still being drawn, shown as it goes.
    var current: DefectMark? = nil

    var body: some View {
        Canvas { context, size in
            let container = CGRect(origin: .zero, size: size)
            let rect = fills ? DefectMarkPainter.filled(imageSize, in: container) : DefectMarkPainter.fitted(imageSize, in: container)
            let width = DefectMarkPainter.lineWidth(in: rect)
            for mark in marks + (current.map { [$0] } ?? []) {
                let path = Path(DefectMarkPainter.path(for: mark, in: rect))
                context.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: width + 1.5, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(DefectMarkPainter.color(mark.colour)), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A defect's photo, whole, with its marks over it.
struct DefectPhotoImage: View {
    let image: UIImage
    let marks: [DefectMark]
    var current: DefectMark? = nil

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                DefectMarksOverlay(marks: marks, imageSize: image.size, current: current)
            }
    }
}

/// A small square of a defect's photo, cropped, with its marks: the list's
/// rows and the new-defect sheet's photos. A grey square with a symbol when
/// there is no photo.
struct DefectThumbnail: View {
    let photo: DefectPhoto?
    var side: CGFloat = 56

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipped()
                DefectMarksOverlay(marks: photo?.marks ?? [], imageSize: image.size, fills: true)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: photo?.id) {
            guard let data = photo?.jpegData, !data.isEmpty else {
                image = nil
                return
            }
            image = DiaryPhotoProcessor.thumbnail(from: data, maxPixel: side * 3)
        }
    }
}

/// Drawing marks on a photo with a finger (Camera board, phone 18): a
/// drag makes the chosen kind of mark in the chosen colour; a tap makes
/// none.
struct DefectMarkingCanvas: View {
    let image: UIImage
    @Binding var marks: [DefectMark]
    let kind: DefectMark.Kind
    let colour: DefectMark.Colour

    @State private var current: DefectMark?

    var body: some View {
        GeometryReader { geometry in
            let container = CGRect(origin: .zero, size: geometry.size)
            let rect = DefectMarkPainter.fitted(image.size, in: container)
            let drawn = DefectRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                DefectMarksOverlay(marks: marks, imageSize: image.size, current: current)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let point = DefectGeometry.normalised(x: value.location.x, y: value.location.y, in: drawn)
                        if var mark = current {
                            if kind == .draw {
                                mark.points.append(point)
                            } else {
                                mark.points = [mark.points.first ?? point, point]
                            }
                            current = mark
                        } else {
                            let start = DefectGeometry.normalised(x: value.startLocation.x, y: value.startLocation.y, in: drawn)
                            current = DefectMark(kind: kind, colour: colour, points: [start, point])
                        }
                    }
                    .onEnded { _ in
                        if let mark = current, mark.isMeaningful { marks.append(mark) }
                        current = nil
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Photo of the defect"))
        .accessibilityHint(String(localized: "Drag around the problem. Optional."))
        .accessibilityIdentifier("defect-mark-canvas")
    }
}

/// Mark the problem (Camera board, phone 18): the photo with Circle, Arrow,
/// Draw and Undo under it and the three colours; Retake and Next at the
/// top. Next without a mark is fine. Also what "Edit marking" opens, with
/// Done instead of Next.
struct DefectMarkingScreen: View {
    let image: UIImage
    @Binding var marks: [DefectMark]
    /// "Retake" while a new defect is being made; "Cancel" when editing.
    let leadingTitle: String
    /// "Next", or "Done" when editing.
    let trailingTitle: String
    let onLeading: () -> Void
    let onTrailing: () -> Void

    @State private var kind: DefectMark.Kind = .circle
    @State private var colour: DefectMark.Colour = .red

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Drag around the problem. Optional.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.vertical, Metrics.small)
                DefectMarkingCanvas(image: image, marks: $marks, kind: kind, colour: colour)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                tools
            }
            .background(Color.black.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .navigationTitle("Mark the problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onLeading) {
                        Text(verbatim: leadingTitle)
                    }
                    .accessibilityIdentifier("defect-mark-retake")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onTrailing) {
                        Text(verbatim: trailingTitle)
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("defect-mark-next")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var tools: some View {
        VStack(spacing: Metrics.medium) {
            HStack(spacing: Metrics.small) {
                toolButton(.circle, title: String(localized: "Circle"), symbol: "circle", identifier: "defect-mark-circle")
                toolButton(.arrow, title: String(localized: "Arrow"), symbol: "arrow.up.right", identifier: "defect-mark-arrow")
                toolButton(.draw, title: String(localized: "Draw"), symbol: "scribble", identifier: "defect-mark-draw")
                Button {
                    if !marks.isEmpty { marks.removeLast() }
                } label: {
                    toolLabel(String(localized: "Undo"), symbol: "arrow.uturn.backward", isOn: false)
                }
                .buttonStyle(.plain)
                .disabled(marks.isEmpty)
                .accessibilityIdentifier("defect-mark-undo")
            }
            HStack(spacing: Metrics.large) {
                ForEach(DefectMark.Colour.allCases, id: \.self) { option in
                    Button {
                        colour = option
                    } label: {
                        Circle()
                            .fill(DefectMarkPainter.color(option))
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: colour == option ? 3 : 0)
                                    .padding(-5)
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(colourName(option))
                    .accessibilityAddTraits(colour == option ? .isSelected : [])
                    .accessibilityIdentifier("defect-mark-colour-\(option.rawValue)")
                }
            }
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.medium)
    }

    private func toolButton(_ option: DefectMark.Kind, title: String, symbol: String, identifier: String) -> some View {
        Button {
            kind = option
        } label: {
            toolLabel(title, symbol: symbol, isOn: kind == option)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kind == option ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func toolLabel(_ title: String, symbol: String, isOn: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title3)
            Text(verbatim: title)
                .font(.caption)
        }
        .foregroundStyle(isOn ? Color.accentColor : Color.white)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(isOn ? Color.white.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
        .contentShape(Rectangle())
    }

    private func colourName(_ colour: DefectMark.Colour) -> String {
        switch colour {
        case .red: return String(localized: "Red")
        case .yellow: return String(localized: "Yellow")
        case .white: return String(localized: "White")
        }
    }
}
