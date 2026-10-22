import SwiftUI
import SwiftData
import PhotosUI

/// Writing down one job of extra work (mockup 14): what was done, the
/// material with big −/+ steppers and a number to tap for 12.5 m, the items
/// used before as chips, optional hours per person, photos, and the client's
/// optional signature — and "Work finished", since a job can run over
/// several days and is in progress until it is ticked.
///
/// A sheet with Cancel and Save, unlike the day screen's diary: a job is a
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
    @State private var people: [ExtraWorkPerson] = []
    @State private var catalog: [ExtraWorkCatalogItem] = []
    @State private var stored: [DiaryThumbnail] = []
    @State private var removedPhotoIDs: Set<UUID> = []
    @State private var pending: [PendingPhoto] = []
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var isAddingPhotos = false
    @State private var showsCamera = false
    @State private var photoToRemove: PhotoReference?
    /// The line whose number was tapped, and what is being typed for it.
    /// Kept apart from the alert's own flag, which the alert clears itself.
    @State private var typedIndex: Int?
    @State private var showsQuantityAlert = false
    @State private var typedText = ""
    @State private var sheet: EditorSheet?
    @State private var confirmsDelete = false
    @State private var path: [ExtraWorkCatalogRoute] = []

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
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.extraLarge) {
                    descriptionSection
                    finishedSection
                    materialSection
                    hoursSection
                    photoSection
                    signatureSection
                    if job != nil { statusSection }
                }
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.large)
                .disabled(!canEdit)
            }
            .background(Color.hoursCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Extra work")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen-extra-work-editor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("extra-work-cancel")
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .fontWeight(.semibold)
                            .disabled(draft.isBlank)
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
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(onPicked: addCameraPhoto)
                .ignoresSafeArea()
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newItem:
                ExtraWorkItemSheet(title: String(localized: "New item"), name: "", unit: .pieces) { name, unit in
                    addItem(name: name, unit: unit)
                }
            case .signature:
                ExtraWorkSignSheet(prompt: String(localized: "Sign to confirm this extra work")) { signature in
                    draft.clientSignature = signature
                }
            }
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
        .confirmationDialog("Remove this photo?", isPresented: Binding(
            get: { photoToRemove != nil }, set: { if !$0 { photoToRemove = nil } }
        ), titleVisibility: .visible) {
            Button("Remove photo", role: .destructive) { removePhoto() }
        }
        .confirmationDialog("Delete this extra work?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteJob)
        } message: {
            Text("Its material, hours, photos and signature are deleted with it.")
        }
    }

    // MARK: - What was done

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("What was done")
            TextField(String(localized: "e.g. Emergency lighting, stairwell"), text: $draft.description, axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, Metrics.medium)
                .frame(minHeight: 48)
                .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel(String(localized: "What was done"))
                .accessibilityIdentifier("extra-work-description")
            Text(verbatim: "\(settingsStore.dateFormatting.dayTitle(draft.date)) · \(site.name)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.leading, Metrics.tiny)
        }
    }

    // MARK: - Finished

    /// Saved with the job, like everything else in the sheet; the day's
    /// checkmark is the quick way that writes at once.
    private var finishedSection: some View {
        Toggle(isOn: Binding(
            get: { draft.isDone },
            set: { isOn in
                draft = isOn ? draft.markingDone(at: Date()) : draft.markingInProgress()
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Work finished")
                    .font(.body)
                Group {
                    if draft.isDone {
                        Text("Finished jobs go in the report to the boss.")
                    } else {
                        Text("In progress until you tick it.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .tint(.green)
        .frame(minHeight: 44)
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .accessibilityIdentifier("extra-work-finished")
    }

    // MARK: - Material

    private var materialSection: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            sectionLabel("Material")
            if !draft.items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(draft.items.enumerated()), id: \.offset) { index, item in
                        materialRow(item, index: index)
                        if index < draft.items.count - 1 {
                            Divider().padding(.leading, Metrics.large)
                        }
                    }
                }
                .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            }

            VStack(alignment: .leading, spacing: Metrics.small) {
                if !suggestions.isEmpty {
                    Text("Used before — tap to add")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, Metrics.tiny)
                }
                ExtraWorkFlow(spacing: Metrics.small) {
                    ForEach(suggestions) { item in
                        Button {
                            addItem(name: item.name, unit: item.unit)
                        } label: {
                            Text(verbatim: "+ \(item.name)")
                                .font(.subheadline)
                                .chipStyle(tint: .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Add \(item.name)", comment: "Extra work: adds a remembered item to the job; the value is its name"))
                    }
                    Button {
                        sheet = .newItem
                    } label: {
                        Text("New item…")
                            .font(.subheadline)
                            .chipStyle(tint: .accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("extra-work-new-item")
                    if !catalog.isEmpty {
                        NavigationLink(value: ExtraWorkCatalogRoute()) {
                            Text("Edit list")
                                .font(.subheadline)
                                .chipStyle(tint: .accentColor)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("extra-work-edit-items")
                    }
                }
            }
        }
    }

    private func materialRow(_ item: ExtraWorkItem, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .font(.body)
                Text(verbatim: item.unit.name(in: .device))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

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
                Text(verbatim: ExtraWorkFormatting.quantity(item.quantity))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 44, minHeight: 44)
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
        .padding(.leading, Metrics.large)
        .padding(.trailing, Metrics.medium)
        .padding(.vertical, 10)
    }

    private var suggestions: [ExtraWorkCatalogItem] {
        Array(ExtraWorkCatalog.suggestions(from: catalog, excluding: draft.items.map(\.name)).prefix(8))
    }

    // MARK: - Hours

    private var hoursSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Metrics.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hours on this job")
                        .font(.body)
                    Text("Optional — leave it out when the material says it all")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if showsHours {
                            draft.hours = []
                            showsHours = false
                        } else {
                            draft.hours = people.map { ExtraWorkHours(memberID: $0.id, name: $0.name, minutes: 0) }
                            showsHours = true
                        }
                    }
                } label: {
                    if showsHours {
                        Text("Remove")
                    } else {
                        Text("Add")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .frame(minHeight: 44)
                .accessibilityIdentifier("extra-work-hours-toggle")
            }
            .padding(.horizontal, Metrics.large)
            .padding(.vertical, Metrics.medium)

            if showsHours {
                ForEach(Array(draft.hours.enumerated()), id: \.offset) { index, entry in
                    Divider().padding(.leading, Metrics.large)
                    HStack(spacing: 10) {
                        Text(verbatim: entry.name)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        RoundStepButton(
                            systemImage: "minus",
                            isProminent: false,
                            label: String(localized: "Less time: \(entry.name)", comment: "Extra work hours stepper; the value is a person's name")
                        ) {
                            draft.hours[index].minutes = max(0, entry.minutes - 15)
                        }
                        Text(verbatim: entry.minutes > 0 ? settingsStore.settings.displayFormatting.string(entry.minutes) : "–")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .frame(minWidth: 64)
                            .accessibilityLabel(String(localized: "Time of \(entry.name)", comment: "Extra work: VoiceOver, a person's time on the job; the value is their name"))
                        RoundStepButton(
                            systemImage: "plus",
                            isProminent: true,
                            label: String(localized: "More time: \(entry.name)", comment: "Extra work hours stepper; the value is a person's name")
                        ) {
                            draft.hours[index].minutes = min(24 * 60, entry.minutes + 15)
                        }
                    }
                    .padding(.leading, Metrics.large)
                    .padding(.trailing, Metrics.medium)
                    .padding(.vertical, Metrics.small)
                    .accessibilityIdentifier("extra-work-hours-\(index)")
                }
                if draft.hours.isEmpty {
                    Divider().padding(.leading, Metrics.large)
                    Text("Nobody is ticked present on this day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(Metrics.large)
                }
            }
        }
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    // MARK: - Photos

    private var photoCount: Int {
        stored.filter { !removedPhotoIDs.contains($0.id) }.count + pending.count
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Photos")
            ExtraWorkFlow(spacing: Metrics.small) {
                ForEach(stored.filter { !removedPhotoIDs.contains($0.id) }) { photo in
                    thumbnail(photo.image, reference: PhotoReference(id: photo.id, isPending: false))
                }
                ForEach(pending) { photo in
                    thumbnail(photo.image, reference: PhotoReference(id: photo.id, isPending: true))
                }
                if canEdit && ExtraWorkJob.photoSlotsLeft(existing: photoCount) > 0 {
                    PhotosPicker(
                        selection: $pickedItems,
                        maxSelectionCount: ExtraWorkJob.photoSlotsLeft(existing: photoCount),
                        matching: .images
                    ) {
                        addTile(systemImage: isAddingPhotos ? "hourglass" : "plus")
                    }
                    .accessibilityLabel(String(localized: "Add photos"))
                    .accessibilityIdentifier("extra-work-add-photos")
                    if CameraPicker.isAvailable {
                        Button {
                            showsCamera = true
                        } label: {
                            addTile(systemImage: "camera")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Take photo"))
                        .accessibilityIdentifier("extra-work-camera")
                    }
                }
            }
        }
    }

    private func thumbnail(_ image: UIImage, reference: PhotoReference) -> some View {
        Button {
            photoToRemove = reference
        } label: {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Extra work photo"))
        .accessibilityHint(String(localized: "Removes it."))
    }

    private func addTile(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(Color.accentColor)
            .frame(width: 84, height: 84)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.hoursHairline, style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .contentShape(Rectangle())
    }

    // MARK: - Client's signature

    private var signatureSection: some View {
        HStack(spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Client's signature")
                    .font(.body)
                if let signature = draft.clientSignature {
                    Text(verbatim: signedLine(signature))
                        .font(.footnote)
                        .foregroundStyle(Color.hoursPositive)
                } else {
                    Text("Optional — the site manager confirms it on your phone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if draft.clientSignature == nil {
                Button("Sign") { sheet = .signature }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("extra-work-sign")
            } else {
                Button("Remove") { draft.clientSignature = nil }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("extra-work-remove-signature")
            }
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.medium)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
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
        VStack(alignment: .leading, spacing: Metrics.small) {
            HStack {
                Text("Status")
                    .font(.body)
                Spacer()
                ExtraWorkChips(job: draft)
            }
            if let sentAt = draft.sentAt, draft.status == .sent {
                Text(String(
                    localized: "Sent to boss on \(settingsStore.dateFormatting.dateWithYear(CalendarDate(sentAt, calendar: settingsStore.workCalendar)))",
                    comment: "Extra work: when the job was last reported to the boss; the value is a date"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Button("Delete this extra work", role: .destructive) { confirmsDelete = true }
                .frame(minHeight: 44)
                .accessibilityIdentifier("extra-work-delete")
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.medium)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    // MARK: - Parts

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, Metrics.tiny)
            .accessibilityAddTraits(.isHeader)
    }

    private var hasChanges: Bool {
        draft != original || !pending.isEmpty || !removedPhotoIDs.isEmpty
    }

    // MARK: - Loading

    private var repository: ExtraWorkRepository { ExtraWorkRepository(context: modelContext) }

    private func load() {
        loadCatalog()
        people = dayPeople()
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

    /// Who can have hours on the job: that day's crew as ticked on the site,
    /// you first; everyone on the site's crew when the day is not written.
    private func dayPeople() -> [ExtraWorkPerson] {
        let sites = SiteRepository(context: modelContext)
        let crew = sites.crew(for: site.id, includeHidden: true)
        let owner = settingsStore.settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let you = ExtraWorkPerson(id: CrewMember.youID, name: owner.isEmpty ? String(localized: "You") : owner)
        let present = sites.siteDay(siteID: site.id, on: date)?.present.map(\.memberID) ?? []
        guard !present.isEmpty else {
            return [you] + crew.filter { !$0.isHidden }.map { ExtraWorkPerson(id: $0.id, name: $0.name) }
        }
        var list: [ExtraWorkPerson] = present.contains(CrewMember.youID) ? [you] : []
        for member in crew where present.contains(member.id) {
            list.append(ExtraWorkPerson(id: member.id, name: member.name))
        }
        return list
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

    private func removePhoto() {
        guard let reference = photoToRemove else { return }
        if reference.isPending {
            pending.removeAll { $0.id == reference.id }
        } else {
            removedPhotoIDs.insert(reference.id)
        }
        photoToRemove = nil
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
            repository.recordUse(of: cleaned.items)
        }
        onDone()
        dismiss()
    }

    private func deleteJob() {
        repository.removeJob(id: draft.id)
        onDone()
        dismiss()
    }
}

/// Someone who can have time on a job.
struct ExtraWorkPerson: Identifiable, Hashable {
    let id: UUID
    let name: String
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
    /// The outlined chip of mockup 14's "Used before".
    func chipStyle(tint: Color) -> some View {
        self
            .foregroundStyle(tint)
            .padding(.horizontal, Metrics.medium)
            .frame(minHeight: 36)
            .overlay {
                Capsule().strokeBorder(Color.hoursHairline, lineWidth: 1)
            }
            .contentShape(Capsule())
            .frame(minHeight: 44)
    }
}
