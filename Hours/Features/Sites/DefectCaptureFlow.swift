import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// The system camera for a defect or a delivery note (1.3): the diary's
/// `UIImagePickerController`, with the picture handed back and Cancel
/// reported, rather than dismissing whatever presented it — here it is one
/// step inside a flow. As with the diary, only the picture is read; its
/// metadata never is.
struct PhotoCaptureCamera: UIViewControllerRepresentable {
    let onPicked: (UIImage) -> Void
    let onCancel: () -> Void

    /// Whether to offer the camera: a device with one, never in the UI
    /// tests, which go without a photo or pick one.
    static var isAvailable: Bool {
        !HoursStack.isRunningUITests && CameraPicker.isAvailable
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {
        context.coordinator.onPicked = onPicked
        context.coordinator.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onPicked: (UIImage) -> Void
        var onCancel: () -> Void

        init(onPicked: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onPicked(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

/// A photo made fit to keep, as the diary's are (`DiaryPhotoProcessor`: at
/// most 1600 pixels, upright, no metadata), with the image it shows.
struct CapturedPhoto: Identifiable {
    let id = UUID()
    let jpegData: Data
    let image: UIImage

    init?(jpegData: Data?) {
        guard let jpegData, let image = UIImage(data: jpegData) else { return nil }
        self.jpegData = jpegData
        self.image = image
    }

    /// From the camera: drawn again at the stored size, upright.
    static func from(_ image: UIImage) -> CapturedPhoto? {
        CapturedPhoto(jpegData: DiaryPhotoProcessor.storedJPEG(from: image))
    }

    /// From the photo picker.
    static func from(_ item: PhotosPickerItem) async -> CapturedPhoto? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        let jpeg = await Task.detached(priority: .userInitiated) { DiaryPhotoProcessor.storedJPEG(from: data) }.value
        return CapturedPhoto(jpegData: jpeg)
    }
}

/// A new defect (Camera board, phones 17–19), full screen from the list's
/// + and the crew's day's "Found a defect": the camera first, with the
/// site's name on it and "From photos"; then the photo to mark; then what
/// and where. Without a camera (the simulator, the UI tests) the first step
/// offers the photo picker and "Without a photo".
struct DefectCaptureFlow: View {
    let site: Site
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Step: Hashable {
        case camera, mark, details
    }

    @State private var step: Step = .camera
    @State private var first: CapturedPhoto?
    @State private var marks: [DefectMark] = []
    @State private var closeUps: [CapturedPhoto] = []
    @State private var picked: PhotosPickerItem?
    @State private var isLoading = false

    var body: some View {
        Group {
            switch step {
            case .camera:
                cameraStep
            case .mark:
                if let first {
                    DefectMarkingScreen(
                        image: first.image,
                        marks: $marks,
                        leadingTitle: String(localized: "Retake"),
                        trailingTitle: String(localized: "Next"),
                        onLeading: retake,
                        onTrailing: { step = .details }
                    )
                }
            case .details:
                DefectDetailsForm(
                    site: site,
                    first: first,
                    marks: marks,
                    closeUps: $closeUps,
                    onEditMarks: { if first != nil { step = .mark } },
                    onCancel: { dismiss() },
                    onAdded: {
                        onAdded()
                        dismiss()
                    }
                )
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            isLoading = true
            Task {
                let photo = await CapturedPhoto.from(item)
                isLoading = false
                guard let photo else { return }
                use(photo)
            }
        }
    }

    // MARK: - The camera

    @ViewBuilder
    private var cameraStep: some View {
        if PhotoCaptureCamera.isAvailable {
            ZStack {
                PhotoCaptureCamera(
                    onPicked: { image in
                        if let photo = CapturedPhoto.from(image) { use(photo) }
                    },
                    onCancel: { dismiss() }
                )
                .ignoresSafeArea()
                VStack {
                    sitePill
                        .padding(.top, 56)
                    Spacer()
                    HStack {
                        fromPhotos
                            .foregroundStyle(.white)
                            .padding(.horizontal, Metrics.medium)
                            .frame(minHeight: 44)
                            .background(Color.black.opacity(0.55), in: Capsule())
                        Spacer()
                    }
                    .padding(.horizontal, Metrics.large)
                    .padding(.bottom, 140)
                }
                if isLoading { ProgressView().tint(.white) }
            }
            .background(Color.black.ignoresSafeArea())
        } else {
            noCamera
        }
    }

    /// "Defect · Trg Pravde" over the camera.
    private var sitePill: some View {
        Text(String(localized: "Defect · \(site.name)", comment: "Over the defect camera; the value is the site's name"))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, Metrics.medium)
            .padding(.vertical, Metrics.tiny + 2)
            .background(Color.black.opacity(0.55), in: Capsule())
            .accessibilityIdentifier("defect-camera-site")
    }

    private var fromPhotos: some View {
        PhotosPicker(selection: $picked, matching: .images) {
            Label(String(localized: "From photos"), systemImage: "photo.on.rectangle")
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier("defect-camera-photos")
    }

    /// Where there is no camera: the photo picker, or a defect noted
    /// without a photo.
    private var noCamera: some View {
        NavigationStack {
            VStack(spacing: Metrics.large) {
                Spacer()
                Image(systemName: "camera")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("There's no camera here. Pick a photo, or note the defect without one.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Metrics.extraLarge)
                if isLoading { ProgressView() }
                Spacer()
                VStack(spacing: Metrics.small) {
                    PhotosPicker(selection: $picked, matching: .images) {
                        Text("From photos")
                    }
                    .buttonStyle(.bigAction(.primary))
                    .accessibilityIdentifier("defect-camera-photos")
                    Button {
                        step = .details
                    } label: {
                        Text("Without a photo")
                    }
                    .buttonStyle(.bigAction(.secondary))
                    .accessibilityIdentifier("defect-camera-skip")
                }
                .padding(.horizontal, Metrics.large)
                .padding(.bottom, Metrics.small)
            }
            .frame(maxWidth: .infinity)
            .background(Color.hoursCanvas)
            .accessibilityIdentifier("screen-defect-camera")
            .navigationTitle(Text(String(localized: "Defect · \(site.name)", comment: "Over the defect camera; the value is the site's name")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("defect-camera-cancel")
                }
            }
        }
    }

    private func use(_ photo: CapturedPhoto) {
        first = photo
        marks = []
        step = .mark
    }

    private func retake() {
        first = nil
        marks = []
        step = .camera
    }
}

/// Say what and where (Camera board, phone 19): the photos with "+
/// Close-up", "What's wrong" with this site's earlier defects as chips, the
/// floor and the room as chips, who fixes it (only while the site assigns
/// defects), who noted it, and Add defect.
struct DefectDetailsForm: View {
    let site: Site
    let first: CapturedPhoto?
    let marks: [DefectMark]
    @Binding var closeUps: [CapturedPhoto]
    let onEditMarks: () -> Void
    let onCancel: () -> Void
    let onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @State private var what = ""
    @State private var floor = ""
    @State private var room = ""
    @State private var assignee: DefectAssignee = .nobody
    @State private var notedBy = ""
    @State private var crew: [String] = []
    @State private var whatChips: [String] = []
    @State private var roomChips: [String] = []
    @State private var typesRoom = false
    @State private var showsCamera = false
    @State private var picked: PhotosPickerItem?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case what, room }

    var body: some View {
        NavigationStack {
            Form {
                photosSection
                whatSection
                whereSection
                if setup.assignsDefects {
                    fixerSection
                }
                notedBySection
            }
            .accessibilityIdentifier("screen-defect-details")
            .navigationTitle("New defect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("defect-cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: add) {
                    Text("Add defect")
                }
                .buttonStyle(.bigAction(.primary))
                .disabled(DefectList.tidy(what).isEmpty)
                .accessibilityIdentifier("defect-add")
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.small)
                .background(Color.hoursCanvas)
            }
            .onAppear(perform: load)
            .fullScreenCover(isPresented: $showsCamera) {
                PhotoCaptureCamera(
                    onPicked: { image in
                        showsCamera = false
                        if let photo = CapturedPhoto.from(image) { closeUps.append(photo) }
                    },
                    onCancel: { showsCamera = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                picked = nil
                Task { if let photo = await CapturedPhoto.from(item) { closeUps.append(photo) } }
            }
        }
    }

    // MARK: - Sections

    private var photoCount: Int { (first == nil ? 0 : 1) + closeUps.count }

    @ViewBuilder
    private var photosSection: some View {
        if first != nil || !closeUps.isEmpty || photoCount < DefectPhoto.maximumBefore {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.small) {
                        if let first {
                            Button(action: onEditMarks) {
                                photoTile(first.image, marks: marks)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Edit marking"))
                            .accessibilityIdentifier("defect-photo-0")
                        }
                        ForEach(Array(closeUps.enumerated()), id: \.element.id) { index, photo in
                            photoTile(photo.image, marks: [])
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        closeUps.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .frame(width: 44, height: 44)
                                    }
                                    .accessibilityLabel(String(localized: "Remove photo"))
                                }
                        }
                        if photoCount < DefectPhoto.maximumBefore {
                            closeUpButton
                        }
                    }
                    .padding(.vertical, Metrics.tiny)
                }
            }
        }
    }

    private func photoTile(_ image: UIImage, marks: [DefectMark]) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 96)
            .overlay { DefectMarksOverlay(marks: marks, imageSize: image.size, fills: true) }
            .clipShape(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var closeUpButton: some View {
        let label = VStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.title3)
            Text(first == nil && closeUps.isEmpty ? String(localized: "Photo") : String(localized: "Close-up"))
                .font(.caption)
        }
        .foregroundStyle(Color.accentColor)
        .frame(width: 96, height: 96)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
        if PhotoCaptureCamera.isAvailable {
            Menu {
                Button {
                    showsCamera = true
                } label: {
                    Label(String(localized: "Take photo"), systemImage: "camera")
                }
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(String(localized: "From photos"), systemImage: "photo.on.rectangle")
                }
            } label: {
                label
            }
            .accessibilityLabel(String(localized: "Add a close-up"))
            .accessibilityIdentifier("defect-close-up")
        } else {
            PhotosPicker(selection: $picked, matching: .images) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Add a close-up"))
            .accessibilityIdentifier("defect-close-up")
        }
    }

    private var whatSection: some View {
        Section {
            TextField(String(localized: "e.g. Socket loose"), text: $what, axis: .vertical)
                .lineLimit(1...3)
                .focused($focusedField, equals: .what)
                .submitLabel(.done)
                .accessibilityLabel(String(localized: "What's wrong"))
                .accessibilityIdentifier("defect-what")
            if !whatChips.isEmpty {
                DefectChips(
                    options: whatChips.map { text -> (String, String) in (text, text) },
                    selected: DefectList.tidy(what),
                    identifier: "defect-what-chip"
                ) { what = $0 }
            }
        } header: {
            Text("What's wrong")
        } footer: {
            if !whatChips.isEmpty {
                Text("Suggestions are this site's earlier defects.")
            }
        }
    }

    private var whereSection: some View {
        Section {
            DefectChips(
                options: floors.map { floor -> (String, String) in (floor, floor) },
                selected: floor,
                identifier: "defect-floor"
            ) { choice in
                floor = floor == choice ? "" : choice
            }
            DefectChips(
                options: roomChips.map { room -> (String, String) in (room, room) },
                selected: room,
                identifier: "defect-room",
                trailing: typesRoom ? nil : (String(localized: "+ Room"), "defect-room-add")
            ) { choice in
                if choice == "defect-room-add" {
                    typesRoom = true
                    focusedField = .room
                } else {
                    room = room == choice ? "" : choice
                }
            }
            if typesRoom {
                TextField(String(localized: "Room, e.g. Corridor"), text: $room)
                    .focused($focusedField, equals: .room)
                    .submitLabel(.done)
                    .accessibilityLabel(String(localized: "Room"))
                    .accessibilityIdentifier("defect-room-field")
            }
        } header: {
            Text("Where")
        }
    }

    private var fixerSection: some View {
        Section {
            DefectChips(
                options: fixerOptions,
                selected: fixerKey,
                identifier: "defect-fixer"
            ) { key in
                switch key {
                case "you": assignee = .you
                case "later": assignee = .nobody
                default: assignee = .person(String(key.dropFirst("person:".count)))
                }
            }
        } header: {
            Text("Who fixes it")
        }
    }

    private var notedBySection: some View {
        Section {
            DefectChips(
                options: notedByOptions,
                selected: notedBy,
                identifier: "defect-noted-by"
            ) { notedBy = $0 }
        } header: {
            Text("Noted by")
        }
    }

    // MARK: - State

    private var setup: SiteSetup {
        settingsStore.settings.siteSetup(for: site.id)
    }

    private var floors: [String] {
        setup.floorList(defaults: SiteFloorNames.defaults)
    }

    /// Me, the crew, Later.
    private var fixerOptions: [(String, String)] {
        var options: [(String, String)] = [(String(localized: "Me"), "you")]
        options += crew.map { name -> (String, String) in (name, "person:" + name) }
        options.append((String(localized: "Later"), "later"))
        return options
    }

    /// You, then the crew.
    private var notedByOptions: [(String, String)] {
        var options: [(String, String)] = [(String(localized: "You"), "")]
        options += crew.map { name -> (String, String) in (name, name) }
        return options
    }

    private var fixerKey: String {
        switch assignee {
        case .nobody: return "later"
        case .you: return "you"
        case let .person(name): return "person:" + name
        }
    }

    private func load() {
        crew = SiteRepository(context: modelContext).crew(for: site.id, includeHidden: false).map(\.name)
        let earlier = DefectRepository(context: modelContext).defects(siteID: site.id)
        whatChips = DefectList.whatSuggestions(earlier, limit: 6)
        roomChips = DefectList.roomSuggestions(earlier, remembered: setup.rooms, limit: 8)
        typesRoom = roomChips.isEmpty
    }

    private func add() {
        let draft = DefectDraft(what: what, floor: floor, room: room, assignee: setup.assignsDefects ? assignee : .nobody, notedBy: notedBy)
        var photos: [(jpegData: Data, marks: [DefectMark])] = []
        if let first { photos.append((jpegData: first.jpegData, marks: marks)) }
        photos += closeUps.map { (jpegData: $0.jpegData, marks: [DefectMark]()) }
        guard DefectRepository(context: modelContext).add(draft, siteID: site.id, photos: photos) != nil else { return }
        let siteID = site.id
        let room = self.room
        settingsStore.update { settings in
            var next = settings.siteSetup(for: siteID)
            let remembered = DefectList.remembering(room: room, in: next.rooms)
            guard remembered != next.rooms else { return }
            next.rooms = remembered
            settings.setSiteSetup(next, for: siteID)
        }
        onAdded()
    }
}

/// Chips that wrap: one is chosen (filled) or none. Each option is a title
/// and the key handed back; `trailing` adds one more chip in the accent,
/// such as "+ Room", handing back its identifier.
struct DefectChips: View {
    let options: [(title: String, key: String)]
    let selected: String
    let identifier: String
    var trailing: (title: String, identifier: String)? = nil
    let onPick: (String) -> Void

    init(
        options: [(String, String)],
        selected: String,
        identifier: String,
        trailing: (String, String)? = nil,
        onPick: @escaping (String) -> Void
    ) {
        self.options = options.map { (title: $0.0, key: $0.1) }
        self.selected = selected
        self.identifier = identifier
        self.trailing = trailing.map { (title: $0.0, identifier: $0.1) }
        self.onPick = onPick
    }

    var body: some View {
        ExtraWorkFlow(spacing: Metrics.small) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isOn = selected == option.key
                Button {
                    onPick(option.key)
                } label: {
                    Text(verbatim: option.title)
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .padding(.horizontal, Metrics.medium)
                        .frame(minHeight: 34)
                        .background(isOn ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("\(identifier)-\(index)")
            }
            if let trailing {
                Button {
                    onPick(trailing.identifier)
                } label: {
                    Text(verbatim: trailing.title)
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, Metrics.small)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(trailing.identifier)
            }
        }
        .padding(.vertical, Metrics.tiny)
    }
}
