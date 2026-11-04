import SwiftUI
import SwiftData
import PhotosUI

/// Writing down one job of extra work (scan board, phone 1), as a form:
/// What was done; the material, each line's quantity (−/+, or tap the number
/// for 12.5 m), then Scan and Add from list, and the items used before as
/// chips to tap; How long it took and who was on it; Finished, since a job
/// can run over several days and is in progress until it is ticked; Photos;
/// and the client's optional signature.
///
/// A sheet with ✕ and ✓, unlike the day screen's diary: a job is a
/// thing written in one go and handed on, and a half-counted job saved on
/// every tap would be in the next report before it was finished. Nothing is
/// written until Save — photos included, which wait in memory.
struct ExtraWorkEditorSheet: View {
    let site: Site
    let date: CalendarDate
    /// `nil` writes a new job.
    let job: ExtraWorkJob?
    let canEdit: Bool
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ExtraWorkJob
    /// What the sheet opened on, to tell whether anything changed.
    @State private var original: ExtraWorkJob
    @State private var showsHours: Bool
    /// Everyone offered under "Who was on it": the day's crew, and anyone
    /// already on the job who is not in it any more.
    @State private var people: [ExtraWorkPerson] = []
    /// Who was on it, by `ExtraWorkPerson.id`.
    @State private var chosen: Set<String> = []
    /// Who is chosen when the time is added: the day's ticked crew.
    @State private var dayCrew: Set<String> = []
    /// How long the job took. An older job whose people have different
    /// minutes opens on the largest (`ExtraWorkJob.duration`); it is stored
    /// as one time for everyone only once the time or the people are changed.
    @State private var minutes: Int
    @State private var showsTimeAlert = false
    @State private var typedTime = ""
    @State private var loaded = false
    @State private var catalog: [ExtraWorkCatalogItem] = []
    @State private var stored: [DiaryThumbnail] = []
    @State private var removedPhotoIDs: Set<UUID> = []
    @State private var pending: [PendingPhoto] = []
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var isAddingPhotos = false
    @State private var showsCamera = false
    /// The photo open full size; removing it is in there, confirmed.
    @State private var viewing: ViewedPhoto?
    /// The line whose number was tapped, and what is being typed for it.
    /// Kept apart from the alert's own flag, which the alert clears itself.
    @State private var typedIndex: Int?
    @State private var showsQuantityAlert = false
    @State private var typedText = ""
    @State private var sheet: EditorSheet?
    @State private var confirmsDelete = false
    @State private var path: [ExtraWorkCatalogRoute] = []
    /// The barcode scanner, full screen (1.3).
    @State private var isScanning = false

    private enum EditorSheet: String, Identifiable {
        case newItem, signature
        var id: String { rawValue }
    }

    private struct PendingPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
        let data: Data
    }

    private struct PhotoReference: Identifiable {
        let id: UUID
        let isPending: Bool
    }

    /// A photo shown full size: which one, and its stored JPEG.
    private struct ViewedPhoto: Identifiable {
        let reference: PhotoReference
        let data: Data
        var id: UUID { reference.id }
    }

    init(site: Site, date: CalendarDate, job: ExtraWorkJob?, canEdit: Bool, onDone: @escaping () -> Void) {
        self.site = site
        self.date = date
        self.job = job
        self.canEdit = canEdit
        self.onDone = onDone
        // A new job starts in progress (`isDone` is false by default).
        let initial = job ?? ExtraWorkJob(siteID: site.id, date: date, isDone: false)
        _draft = State(initialValue: initial)
        _original = State(initialValue: initial)
        _showsHours = State(initialValue: job?.hasHours ?? false)
        _minutes = State(initialValue: job?.duration ?? 0)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                // A read-only site's job can still be looked through;
                // nothing in it changes.
                descriptionSection
                    .disabled(!canEdit)
                materialSection
                    .disabled(!canEdit)
                materialActions
                    .disabled(!canEdit)
                usedBeforeSection
                    .disabled(!canEdit)
                timeSection
                    .disabled(!canEdit)
                if showsHours {
                    whoSection
                        .disabled(!canEdit)
                }
                finishedSection
                    .disabled(!canEdit)
                if canEdit || photoCount > 0 {
                    photoSection
                }
                signatureSection
                    .disabled(!canEdit)
                if job != nil {
                    statusSection
                        .disabled(!canEdit)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("screen-extra-work-editor")
            .navigationTitle("Extra work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("extra-work-cancel")
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: save) {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        // Prominent: the accent, filled. iOS 18 API, so it
                        // builds with either SDK.
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .disabled(draft.isBlank)
                        .accessibilityLabel(String(localized: "Save"))
                        .accessibilityIdentifier("extra-work-save")
                    }
                }
            }
            .navigationDestination(for: ExtraWorkCatalogRoute.self) { _ in
                ExtraWorkCatalogScreen(onChange: loadCatalog)
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .onAppear(perform: load)
        .onChange(of: pickedItems) { _, items in addPicked(items) }
        // On the stack rather than on a row: a list only keeps the rows on
        // screen, and a presentation on a row scrolled away would close.
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(onPicked: addCameraPhoto)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isScanning) {
            ExtraWorkScannerSheet(items: $draft.items, onCatalogChange: loadCatalog)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newItem:
                ExtraWorkItemSheet(title: String(localized: "New item"), name: "", unit: .pieces) { name, unit in
                    addItem(name: name, unit: unit)
                }
            case .signature:
                ExtraWorkSignSheet(
                    prompt: String(localized: "Sign to confirm this extra work"),
                    summary: signSummary
                ) { signature in
                    draft.clientSignature = signature
                }
            }
        }
        // A tap on a photo shows it; removing it is a button in there, with
        // a confirmation. Removing waits for Save, like everything here.
        .sheet(item: $viewing) { photo in
            PhotoViewerSheet(
                data: photo.data,
                spokenName: String(localized: "Extra work photo"),
                onRemove: canEdit ? { removePhoto(photo.reference) } : nil
            )
        }
        .alert("Quantity", isPresented: $showsQuantityAlert) {
            TextField(String(localized: "Quantity"), text: $typedText)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("extra-work-quantity-field")
            Button("Cancel", role: .cancel) {}
            Button("OK") { applyTypedQuantity() }
        } message: {
            if let typedIndex, draft.items.indices.contains(typedIndex) {
                Text(verbatim: draft.items[typedIndex].name)
            }
        }
        .alert("Time on this job", isPresented: $showsTimeAlert) {
            TextField(String(localized: "e.g. 1:30"), text: $typedTime)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("extra-work-time-field")
            Button("Cancel", role: .cancel) {}
            Button("OK") {
                guard let typed = ExtraWorkTime.parse(typedTime) else { return }
                minutes = typed
                applyTime()
            }
        } message: {
            Text("Hours and minutes, such as 1:30, or hours, such as 1.5.")
        }
        .confirmationDialog("Delete this extra work?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteJob)
        } message: {
            Text("Its material, hours, photos and signature are deleted with it.")
        }
    }

    // MARK: - What was done

    /// What was done, with Scan text beside the field; the day and the
    /// site under it.
    private var descriptionSection: some View {
        Section {
            HStack(alignment: .top, spacing: Metrics.small) {
                TextField(String(localized: "e.g. Emergency lighting, stairwell"), text: $draft.description, axis: .vertical)
                    .lineLimit(1...4)
                    .frame(minHeight: 32)
                    .accessibilityLabel(String(localized: "What was done"))
                    .accessibilityIdentifier("extra-work-description")
                ScanTextButton(identifier: "extra-work-description-scan-text") { text in
                    draft.description = text
                }
            }
        } header: {
            Text("What was done")
                .textCase(nil)
        } footer: {
            Text(verbatim: "\(settingsStore.dateFormatting.dayTitle(draft.date)) · \(site.name)")
        }
    }

    // MARK: - Finished

    /// Saved with the job, like everything else in the sheet; the day's
    /// checkmark is the quick way that writes at once.
    private var finishedSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { draft.isDone },
                set: { isOn in
                    draft = isOn ? draft.markingDone(at: Date()) : draft.markingInProgress()
                }
            )) {
                Text("Finished")
            }
            .accessibilityIdentifier("extra-work-finished")
        }
    }

    // MARK: - Material

    /// The job's lines: the name, "scanned" when its box has a code, and
    /// −, the amount in its unit, +.
    private var materialSection: some View {
        Section {
            ForEach(Array(draft.items.enumerated()), id: \.offset) { index, item in
                materialRow(item, index: index)
            }
        } header: {
            Text("Material")
                .textCase(nil)
        }
    }

    /// Scan and Add from list, side by side under the material, on the
    /// background as on the board.
    private var materialActions: some View {
        Section {
            HStack(spacing: Metrics.small) {
                // Scanning (1.3): each code read adds one of its item.
                Button {
                    isScanning = true
                } label: {
                    Label("Scan", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(.bigAction(.secondary))
                .accessibilityHint(String(localized: "Scan the barcodes on the boxes; each one adds one to the job."))
                .accessibilityIdentifier("extra-work-scan")

                Menu {
                    ForEach(listItems) { item in
                        Button {
                            addItem(name: item.name, unit: item.unit)
                        } label: {
                            Text(verbatim: item.name)
                        }
                    }
                    if !listItems.isEmpty {
                        Divider()
                    }
                    Button {
                        sheet = .newItem
                    } label: {
                        Label("New item…", systemImage: "plus")
                    }
                    if !catalog.isEmpty {
                        Button {
                            path.append(ExtraWorkCatalogRoute())
                        } label: {
                            Label("Edit list", systemImage: "pencil")
                        }
                    }
                } label: {
                    Text("Add from list")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, Metrics.medium)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                        .contentShape(Capsule())
                }
                .accessibilityIdentifier("extra-work-add-from-list")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// Used before: the remembered items as chips to tap, "+ New" and
    /// "Edit list", wrapping on the background.
    private var usedBeforeSection: some View {
        Section {
            ExtraWorkFlow(spacing: Metrics.small) {
                ForEach(suggestions) { item in
                    Button {
                        addItem(name: item.name, unit: item.unit)
                    } label: {
                        Text(verbatim: "+ \(item.name)")
                            .font(.subheadline.weight(.medium))
                            .chipStyle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Add \(item.name)", comment: "Extra work: adds a remembered item to the job; the value is its name"))
                }
                Button {
                    sheet = .newItem
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .chipStyle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "New item…"))
                .accessibilityIdentifier("extra-work-new-item")
                if !catalog.isEmpty {
                    NavigationLink(value: ExtraWorkCatalogRoute()) {
                        Text("Edit list")
                            .font(.subheadline.weight(.medium))
                            .chipStyle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("extra-work-edit-items")
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            if !suggestions.isEmpty {
                Text("Used before")
                    .textCase(nil)
            }
        }
    }

    private func materialRow(_ item: ExtraWorkItem, index: Int) -> some View {
        HStack(spacing: Metrics.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                // An item whose box has a code on it, as on the board.
                if isScanned(item) {
                    Text("scanned")
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RoundStepButton(
                systemImage: item.quantity > 0 ? "minus" : "trash",
                isProminent: false,
                label: item.quantity > 0
                    ? String(localized: "One fewer: \(item.name)", comment: "Extra work stepper; the value is the item's name")
                    : String(localized: "Remove \(item.name)", comment: "Extra work: removes a line of material; the value is the item's name")
            ) {
                if item.quantity > 0 {
                    draft.items[index].quantity = ExtraWorkQuantity.stepped(item.quantity, by: -1)
                } else {
                    draft.items.remove(at: index)
                }
            }
            .accessibilityIdentifier("extra-work-minus-\(index)")

            Button {
                typedText = ExtraWorkFormatting.quantity(item.quantity)
                typedIndex = index
                showsQuantityAlert = true
            } label: {
                Text(verbatim: "\(ExtraWorkFormatting.quantity(item.quantity)) \(item.unit.name(in: .device))")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 56, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Quantity of \(item.name)", comment: "Extra work: VoiceOver, the number to tap to type a quantity; the value is the item's name"))
            .accessibilityValue(Text(verbatim: "\(ExtraWorkFormatting.quantity(item.quantity)) \(item.unit.name(in: .device))"))
            .accessibilityHint(String(localized: "Type an amount, such as 12.5."))
            .accessibilityIdentifier("extra-work-quantity-\(index)")

            RoundStepButton(
                systemImage: "plus",
                isProminent: true,
                label: String(localized: "One more: \(item.name)", comment: "Extra work stepper; the value is the item's name")
            ) {
                draft.items[index].quantity = ExtraWorkQuantity.stepped(item.quantity, by: 1)
            }
            .accessibilityIdentifier("extra-work-plus-\(index)")
        }
    }

    /// The site's own items first (1.3), then the most recently used.
    private var suggestions: [ExtraWorkCatalogItem] {
        Array(listItems.prefix(8))
    }

    /// Everything remembered that is not on the job yet, for Add from list.
    private var listItems: [ExtraWorkCatalogItem] {
        ExtraWorkCatalog.suggestions(from: catalog, excluding: draft.items.map(\.name), siteID: site.id)
    }

    private func isScanned(_ item: ExtraWorkItem) -> Bool {
        let key = ExtraWorkCatalog.key(item.name)
        return catalog.contains { $0.hasBarcode && ExtraWorkCatalog.key($0.name) == key }
    }

    // MARK: - Time on this job

    /// "It took us an hour": one time for the job, however many were on it,
    /// and who was. Saved as each chosen person with that same time, in the
    /// job's existing hours list (`ExtraWorkJob.settingTime`).
    private var timeSection: some View {
        Section {
            if showsHours {
                timeStepper
            }
            Button(role: showsHours ? .destructive : nil) {
                withAnimation(.snappy(duration: 0.2)) {
                    if showsHours {
                        draft.hours = []
                        minutes = 0
                        chosen = []
                        showsHours = false
                    } else {
                        chosen = dayCrew
                        showsHours = true
                        applyTime()
                    }
                }
            } label: {
                if showsHours {
                    Text("Remove")
                } else {
                    Text("Add")
                }
            }
            .accessibilityIdentifier("extra-work-hours-toggle")
        } header: {
            Text("How long it took")
                .textCase(nil)
        } footer: {
            Text("Optional — leave it out when the material says it all")
        }
    }

    /// One −/+ for the whole job, a quarter of an hour a step; the number
    /// can be tapped to type a time.
    private var timeStepper: some View {
        HStack(spacing: Metrics.small) {
            Text("Time")
                .frame(maxWidth: .infinity, alignment: .leading)
            RoundStepButton(
                systemImage: "minus",
                isProminent: false,
                label: String(localized: "Less time")
            ) {
                minutes = ExtraWorkTime.stepped(minutes, by: -1)
                applyTime()
            }
            .accessibilityIdentifier("extra-work-time-minus")
            Button {
                typedTime = ExtraWorkTime.typingText(minutes)
                showsTimeAlert = true
            } label: {
                Text(verbatim: minutes > 0 ? settingsStore.settings.displayFormatting.string(minutes) : "–")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 64, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Time on this job"))
            .accessibilityValue(Text(verbatim: minutes > 0 ? settingsStore.settings.displayFormatting.string(minutes) : "–"))
            .accessibilityHint(String(localized: "Type a time, such as 1:30."))
            .accessibilityIdentifier("extra-work-time")
            RoundStepButton(
                systemImage: "plus",
                isProminent: true,
                label: String(localized: "More time")
            ) {
                minutes = ExtraWorkTime.stepped(minutes, by: 1)
                applyTime()
            }
            .accessibilityIdentifier("extra-work-time-plus")
        }
    }

    /// The day's crew as rows to tick: everyone ticked present that day is
    /// chosen when the time is added.
    private var whoSection: some View {
        Section {
            if people.isEmpty {
                Text("Nobody is ticked present on this day.")
                    .foregroundStyle(.hoursSecondaryText)
            } else {
                ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                    personRow(person)
                        .accessibilityIdentifier("extra-work-person-\(index)")
                }
            }
        } header: {
            Text("Who was on it")
                .textCase(nil)
        }
    }

    private func personRow(_ person: ExtraWorkPerson) -> some View {
        let isChosen = chosen.contains(person.id)
        return Button {
            if isChosen { chosen.remove(person.id) } else { chosen.insert(person.id) }
            applyTime()
        } label: {
            HStack(spacing: Metrics.medium) {
                Text(verbatim: person.name)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isChosen {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: person.name))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// The time and the people chosen, into the draft: everyone chosen with
    /// the same minutes, in the order they are offered.
    private func applyTime() {
        let onIt = people.filter { chosen.contains($0.id) }.map { ExtraWorkHours(memberID: $0.memberID, name: $0.name, minutes: 0) }
        draft = draft.settingTime(minutes, for: onIt)
    }

    // MARK: - Photos

    private var photoCount: Int {
        stored.filter { !removedPhotoIDs.contains($0.id) }.count + pending.count
    }

    /// Photos: the pictures in a grid row, then Add photos and the camera.
    private var photoSection: some View {
        Section {
            if photoCount > 0 {
                ExtraWorkFlow(spacing: Metrics.small) {
                    ForEach(stored.filter { !removedPhotoIDs.contains($0.id) }) { photo in
                        thumbnail(photo.image, photo: ViewedPhoto(reference: PhotoReference(id: photo.id, isPending: false), data: photo.data))
                    }
                    ForEach(pending) { photo in
                        thumbnail(photo.image, photo: ViewedPhoto(reference: PhotoReference(id: photo.id, isPending: true), data: photo.data))
                    }
                }
                .padding(.vertical, Metrics.tiny)
            }
            if canEdit && ExtraWorkJob.photoSlotsLeft(existing: photoCount) > 0 {
                HStack(spacing: Metrics.medium) {
                    PhotosPicker(
                        selection: $pickedItems,
                        maxSelectionCount: ExtraWorkJob.photoSlotsLeft(existing: photoCount),
                        matching: .images
                    ) {
                        HStack(spacing: Metrics.small) {
                            Text("Add photos")
                            if isAddingPhotos {
                                ProgressView()
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    // Its own tap target, not the whole row's.
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(localized: "Add photos"))
                    .accessibilityIdentifier("extra-work-add-photos")
                    Spacer(minLength: Metrics.small)
                    if CameraPicker.isAvailable {
                        Button {
                            showsCamera = true
                        } label: {
                            Image(systemName: "camera")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(localized: "Take photo"))
                        .accessibilityIdentifier("extra-work-camera")
                    }
                }
            }
        } header: {
            Text("Photos")
                .textCase(nil)
        }
    }

    private func thumbnail(_ image: UIImage, photo: ViewedPhoto) -> some View {
        Button {
            viewing = photo
        } label: {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Extra work photo"))
        .accessibilityIdentifier("extra-work-photo")
    }

    // MARK: - Client's signature

    private var signatureSection: some View {
        Section {
            HStack(spacing: Metrics.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Client's signature")
                    if let signature = draft.clientSignature {
                        Text(verbatim: signedLine(signature))
                            .font(.subheadline)
                            .foregroundStyle(.hoursSecondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if draft.clientSignature != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.hoursDone)
                        .accessibilityHidden(true)
                    Button("Remove") { draft.clientSignature = nil }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("extra-work-remove-signature")
                } else {
                    Button("Sign") { sheet = .signature }
                        .buttonStyle(.borderless)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("extra-work-sign")
                }
            }
        } footer: {
            if draft.clientSignature == nil {
                Text("Optional — the site manager confirms it on your phone")
            }
        }
    }

    private func signedLine(_ signature: ExtraWorkSignature) -> String {
        let name = signature.signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let day = settingsStore.dateFormatting.shortDate(CalendarDate(signature.signedAt, calendar: settingsStore.workCalendar))
        return name.isEmpty
            ? String(localized: "Signed \(day)", comment: "Extra work: when the client signed; the value is a date")
            : String(localized: "Signed by \(name) · \(day)", comment: "Extra work: who signed and when; the values are a name and a date")
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                ExtraWorkChips(job: draft)
            }
            Button("Delete this extra work", role: .destructive) { confirmsDelete = true }
                .accessibilityIdentifier("extra-work-delete")
        } footer: {
            if let sentAt = draft.sentAt, draft.status == .sent {
                Text(String(
                    localized: "Sent to boss on \(settingsStore.dateFormatting.dateWithYear(CalendarDate(sentAt, calendar: settingsStore.workCalendar)))",
                    comment: "Extra work: when the job was last reported to the boss; the value is a date"
                ))
            }
        }
    }


    // MARK: - Parts

    /// Under WHO SIGNS: what is being signed for, "Emergency lighting ·
    /// Thu 29 Oct · 2h 30m".
    private var signSummary: String {
        var parts: [String] = []
        let title = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { parts.append(title) }
        parts.append(settingsStore.dateFormatting.dayTitle(draft.date))
        if draft.duration > 0 { parts.append(settingsStore.settings.displayFormatting.string(draft.duration)) }
        return parts.joined(separator: " · ")
    }

    private var hasChanges: Bool {
        draft != original || !pending.isEmpty || !removedPhotoIDs.isEmpty
    }

    // MARK: - Loading

    private var repository: ExtraWorkRepository { ExtraWorkRepository(context: modelContext) }

    private func load() {
        loadCatalog()
        // Once: coming back from the remembered items must not undo who was
        // picked.
        guard !loaded else { return }
        loaded = true
        let day = dayPeople()
        dayCrew = day.chosen
        people = day.people
        // Anyone already on the job who is not offered for the day any more
        // (taken off the crew, or a name typed on an older job) stays a chip.
        for entry in draft.hours where entry.minutes > 0 {
            let person = ExtraWorkPerson(memberID: entry.memberID, name: entry.name)
            if !people.contains(where: { $0.id == person.id }) { people.append(person) }
        }
        chosen = Set(draft.hours.filter { $0.minutes > 0 }.map { ExtraWorkPerson(memberID: $0.memberID, name: $0.name).id })
        if let job {
            stored = repository.photos(jobID: job.id).compactMap { photo in
                guard let image = DiaryPhotoProcessor.thumbnail(from: photo.jpegData, maxPixel: 300) else { return nil }
                return DiaryThumbnail(id: photo.id, image: image, data: photo.jpegData)
            }
        }
    }

    private func loadCatalog() {
        catalog = repository.catalog()
    }

    /// Who can be on the job: that day's crew as ticked on the site, you
    /// first, all of them chosen when the time is added; everyone on the
    /// site's crew when the day is not written, with only you chosen.
    private func dayPeople() -> (people: [ExtraWorkPerson], chosen: Set<String>) {
        let sites = SiteRepository(context: modelContext)
        let crew = sites.crew(for: site.id, includeHidden: true)
        let owner = settingsStore.settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let you = ExtraWorkPerson(memberID: CrewMember.youID, name: owner.isEmpty ? String(localized: "You") : owner)
        let present = sites.siteDay(siteID: site.id, on: date)?.present.map(\.memberID) ?? []
        guard !present.isEmpty else {
            let everyone = [you] + crew.filter { !$0.isHidden }.map { ExtraWorkPerson(memberID: $0.id, name: $0.name) }
            return (everyone, [you.id])
        }
        var list: [ExtraWorkPerson] = present.contains(CrewMember.youID) ? [you] : []
        for member in crew where present.contains(member.id) {
            list.append(ExtraWorkPerson(memberID: member.id, name: member.name))
        }
        return (list, Set(list.map(\.id)))
    }

    // MARK: - Editing

    private func addItem(name: String, unit: ExtraWorkUnit) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = draft.items.firstIndex(where: { ExtraWorkCatalog.key($0.name) == ExtraWorkCatalog.key(trimmed) && $0.unit == unit }) {
            draft.items[index].quantity = ExtraWorkQuantity.stepped(draft.items[index].quantity, by: 1)
        } else {
            draft.items.append(ExtraWorkItem(name: trimmed, quantity: 1, unit: unit))
        }
    }

    private func applyTypedQuantity() {
        guard let typedIndex, draft.items.indices.contains(typedIndex), let value = ExtraWorkQuantity.parse(typedText) else { return }
        draft.items[typedIndex].quantity = value
    }

    private func addPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pickedItems = []
        isAddingPhotos = true
        Task {
            for item in items where ExtraWorkJob.photoSlotsLeft(existing: photoCount) > 0 {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let jpeg = await Task.detached(priority: .userInitiated) {
                    DiaryPhotoProcessor.storedJPEG(from: data)
                }.value
                if let jpeg, let image = DiaryPhotoProcessor.thumbnail(from: jpeg, maxPixel: 300) {
                    pending.append(PendingPhoto(image: image, data: jpeg))
                }
            }
            isAddingPhotos = false
        }
    }

    private func addCameraPhoto(_ image: UIImage) {
        guard ExtraWorkJob.photoSlotsLeft(existing: photoCount) > 0,
              let jpeg = DiaryPhotoProcessor.storedJPEG(from: image),
              let thumbnail = DiaryPhotoProcessor.thumbnail(from: jpeg, maxPixel: 300) else { return }
        pending.append(PendingPhoto(image: thumbnail, data: jpeg))
    }

    private func removePhoto(_ reference: PhotoReference) {
        if reference.isPending {
            pending.removeAll { $0.id == reference.id }
        } else {
            removedPhotoIDs.insert(reference.id)
        }
    }

    private func save() {
        guard canEdit else { return }
        var next = draft
        if !showsHours { next.hours = [] }
        let cleaned = next.cleaned()
        let repository = self.repository
        repository.storeJob(next)
        if !cleaned.isBlank {
            for id in removedPhotoIDs { repository.removePhoto(id: id) }
            for photo in pending { repository.addPhoto(photo.data, jobID: next.id, siteID: site.id) }
            repository.recordUse(of: cleaned.items, siteID: site.id)
        }
        refreshUnsentWorkReminder()
        onDone()
        dismiss()
    }

    private func deleteJob() {
        repository.removeJob(id: draft.id)
        refreshUnsentWorkReminder()
        onDone()
        dismiss()
    }

    /// A job saved, finished or deleted changes what the weekly "extra work
    /// not sent" note says, or whether there is one.
    private func refreshUnsentWorkReminder() {
        let context = modelContext
        let settings = settingsStore
        Task { await ExtraWorkReminderRefresher.refresh(context: context, settingsStore: settings) }
    }
}

/// Someone who can be on a job.
struct ExtraWorkPerson: Identifiable, Hashable {
    /// A `CrewMember.id`, `CrewMember.youID`, or `nil` for a name typed on
    /// an older job.
    let memberID: UUID?
    let name: String

    /// The member, or for a typed name the name itself.
    var id: String { memberID?.uuidString ?? "name:" + name }
}

/// The value route to the remembered items, pushed inside the editor's own
/// navigation stack.
struct ExtraWorkCatalogRoute: Hashable {}

/// A round −/+ button, 44 points across.
struct RoundStepButton: View {
    let systemImage: String
    let isProminent: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isProminent ? Color.white : Color.primary)
                .frame(width: 44, height: 44)
                .background(isProminent ? Color.accentColor : Color(uiColor: .tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private extension View {
    /// A "Used before" chip: the grouped rows' fill, the accent text.
    func chipStyle() -> some View {
        self
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, Metrics.medium)
            .frame(minHeight: 36)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .contentShape(Capsule())
            .frame(minHeight: 44)
    }
}
