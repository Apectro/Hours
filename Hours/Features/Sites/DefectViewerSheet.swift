import SwiftUI
import SwiftData
import PhotosUI

/// A defect, full screen (Camera board, phone 20): its photos to swipe
/// between — before, then after — each with its marks and pinch to zoom;
/// under them what, where (and who fixes it when the site assigns them),
/// and "Noted by … · date, time". Photo after and Mark fixed at the bottom;
/// a fixed defect offers Reopen. The ⋯ menu edits the marking of the photo
/// shown, or deletes the defect.
struct DefectViewerSheet: View {
    let site: Site
    let defectID: UUID
    let canEdit: Bool
    let onChange: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var defect: Defect?
    @State private var photos: [DefectPhoto] = []
    @State private var index = 0
    @State private var editing: EditingMarks?
    @State private var showsCamera = false
    @State private var picked: PhotosPickerItem?
    @State private var confirmsDelete = false

    private struct EditingMarks: Identifiable {
        let photo: DefectPhoto
        let image: UIImage
        var id: UUID { photo.id }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Metrics.medium) {
                photoPages
                if let defect {
                    caption(defect)
                    if canEdit {
                        buttons(defect)
                    }
                }
            }
            .padding(.bottom, Metrics.small)
            .background(Color.black.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            .accessibilityIdentifier("screen-defect-viewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("defect-viewer-done")
                }
                ToolbarItem(placement: .principal) {
                    Text(verbatim: positionTitle)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("defect-viewer-position")
                }
                if canEdit {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if let current, let image = UIImage(data: current.jpegData) {
                                Button {
                                    editing = EditingMarks(photo: current, image: image)
                                } label: {
                                    Label(String(localized: "Edit marking"), systemImage: "pencil.tip.crop.circle")
                                }
                                .accessibilityIdentifier("defect-viewer-edit-marking")
                            }
                            Button(role: .destructive) {
                                confirmsDelete = true
                            } label: {
                                Label(String(localized: "Delete defect"), systemImage: "trash")
                            }
                            .accessibilityIdentifier("defect-viewer-delete")
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel(String(localized: "More"))
                        .accessibilityIdentifier("defect-viewer-menu")
                    }
                }
            }
            .confirmationDialog(String(localized: "Delete this defect and its photos?"), isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    DefectRepository(context: modelContext).remove(id: defectID)
                    onChange()
                    dismiss()
                }
                .accessibilityIdentifier("defect-viewer-delete-confirm")
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .fullScreenCover(item: $editing) { editing in
            MarkEditor(image: editing.image, initial: editing.photo.marks) { marks in
                DefectRepository(context: modelContext).setMarks(marks, onPhoto: editing.photo.id)
                reload()
                onChange()
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            PhotoCaptureCamera(
                onPicked: { image in
                    showsCamera = false
                    if let photo = CapturedPhoto.from(image) { addAfter(photo) }
                },
                onCancel: { showsCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { if let photo = await CapturedPhoto.from(item) { addAfter(photo) } }
        }
    }

    // MARK: - Photos

    private var current: DefectPhoto? {
        photos.indices.contains(index) ? photos[index] : nil
    }

    /// "Before · 1 of 2", "After · 3 Nov".
    private var positionTitle: String {
        guard let current else { return String(localized: "No photo") }
        let part = current.isAfter ? String(localized: "After") : String(localized: "Before")
        let ofCount = photos.count > 1
            ? String(localized: "\(index + 1) of \(photos.count)", comment: "Defect viewer: which photo of how many")
            : formatting.shortDate(CalendarDate(current.takenAt, calendar: settingsStore.workCalendar))
        return "\(part) · \(ofCount)"
    }

    @ViewBuilder
    private var photoPages: some View {
        if photos.isEmpty {
            VStack(spacing: Metrics.small) {
                Image(systemName: "photo")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text("No photo of this one yet.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                    ZoomableDefectPhoto(photo: photo)
                        .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Caption and buttons

    private var formatting: CalendarFormatting { settingsStore.dateFormatting }

    private func caption(_ defect: Defect) -> some View {
        let showsAssignee = settingsStore.settings.siteSetup(for: site.id).assignsDefects
        let place = [defect.floor, defect.room].filter { !$0.isEmpty }
        let fixer: String? = showsAssignee && defect.assignee != .nobody
            ? String(localized: "\(DefectWords.assignee(defect.assignee)) fixes it", comment: "Defect viewer: who fixes it; the value is a name or Me")
            : nil
        let whereLine = (place + (fixer.map { [$0] } ?? [])).joined(separator: " · ")
        let noted = defect.notedAt
        let day = CalendarDate(noted, calendar: settingsStore.workCalendar)
        let time = noted.formatted(date: .omitted, time: .shortened)
        let who = defect.notedBy.isEmpty ? String(localized: "you", comment: "Who noted a defect, when it was you") : defect.notedBy
        return VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: defect.what)
                .font(.headline)
            if !whereLine.isEmpty {
                Text(verbatim: whereLine)
                    .font(.subheadline)
            }
            Text(String(
                localized: "Noted by \(who) · \(formatting.shortDate(day)), \(time)",
                comment: "Defect viewer: who noted it and when; the values are a name or you, a date and a time"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if defect.state == .fixed, let fixedAt = defect.fixedAt {
                Label {
                    Text(String(
                        localized: "Fixed \(formatting.shortDate(CalendarDate(fixedAt, calendar: settingsStore.workCalendar)))",
                        comment: "Defect viewer: the day it was fixed"
                    ))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.hoursDone)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.large)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .padding(.horizontal, Metrics.large)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("defect-viewer-caption")
    }

    private func buttons(_ defect: Defect) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Metrics.small))
            : AnyLayout(HStackLayout(spacing: Metrics.small))
        return layout {
            photoAfterButton
                .disabled(photos.filter(\.isAfter).count >= DefectPhoto.maximumAfter)
            switch defect.state {
            case .open:
                Button {
                    DefectRepository(context: modelContext).markFixed(defect.id)
                    reload()
                    onChange()
                } label: {
                    Text("Mark fixed")
                }
                .buttonStyle(.bigAction(.primary))
                .accessibilityIdentifier("defect-mark-fixed")
            case .fixed:
                Button {
                    DefectRepository(context: modelContext).reopen(defect.id)
                    reload()
                    onChange()
                } label: {
                    Text("Reopen")
                }
                .buttonStyle(.bigAction(.secondary))
                .accessibilityIdentifier("defect-reopen")
            }
        }
        .padding(.horizontal, Metrics.large)
    }

    @ViewBuilder
    private var photoAfterButton: some View {
        if PhotoCaptureCamera.isAvailable {
            Button {
                showsCamera = true
            } label: {
                Text("Photo after")
            }
            .buttonStyle(.bigAction(.secondary))
            .accessibilityIdentifier("defect-photo-after")
        } else {
            PhotosPicker(selection: $picked, matching: .images) {
                Text("Photo after")
            }
            .buttonStyle(.bigAction(.secondary))
            .accessibilityIdentifier("defect-photo-after")
        }
    }

    // MARK: - Changes

    private func reload() {
        let repository = DefectRepository(context: modelContext)
        defect = repository.defect(id: defectID)
        photos = repository.photos(defectID: defectID)
        if index >= photos.count { index = max(photos.count - 1, 0) }
    }

    private func addAfter(_ photo: CapturedPhoto) {
        guard let defect,
              DefectRepository(context: modelContext).addPhoto(photo.jpegData, to: defect, isAfter: true) != nil
        else { return }
        reload()
        index = photos.count - 1
        onChange()
    }
}

/// "Edit marking": the photo with its marks to change, Cancel and Done.
private struct MarkEditor: View {
    let image: UIImage
    let onDone: ([DefectMark]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var marks: [DefectMark]

    init(image: UIImage, initial: [DefectMark], onDone: @escaping ([DefectMark]) -> Void) {
        self.image = image
        self.onDone = onDone
        _marks = State(initialValue: initial)
    }

    var body: some View {
        DefectMarkingScreen(
            image: image,
            marks: $marks,
            leadingTitle: String(localized: "Cancel"),
            trailingTitle: String(localized: "Done"),
            onLeading: { dismiss() },
            onTrailing: {
                onDone(marks)
                dismiss()
            }
        )
    }
}

/// One photo with its marks, pinched to zoom and double-tapped back.
private struct ZoomableDefectPhoto: View {
    let photo: DefectPhoto

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1

    var body: some View {
        Group {
            if let image {
                DefectPhotoImage(image: image, marks: photo.marks)
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in scale = min(max(settledScale * value.magnification, 1), 4) }
                            .onEnded { _ in settledScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.snappy) {
                            scale = 1
                            settledScale = 1
                        }
                    }
                    .accessibilityLabel(String(localized: "Photo of the defect"))
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: photo.id) {
            image = UIImage(data: photo.jpegData)
        }
    }
}
