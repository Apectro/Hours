import SwiftUI
import SwiftData
import PhotosUI

/// Writing down one job of extra work (mockup 14): what was done, the
/// material with big −/+ steppers and a number to tap for 12.5 m, the items
/// used before as chips, optionally how long the job took and who was on it,
/// photos, and the client's optional signature — and "Work finished", since
/// a job can run over several days and is in progress until it is ticked.
///
/// "What was done" and "Work finished" are always open; Material, Time on
/// this job, Photos and Client's signature are sections that open in place,
/// each saying what is inside while closed ("Items: 3", "1h · 2 people").
/// Material starts open, the rest closed, for a new job and an existing one
/// alike: the summaries tell what an existing job holds.
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
    @State private var expanded: Set<EditorSection> = [.material]
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

    /// The sections that open in place.
    private enum EditorSection: String, Hashable {
        case material, time, photos, signature
    }

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
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.extraLarge) {
                    // A read-only site's job can still be looked through:
                    // the section headers open, what is in them does not
                    // change.
                    descriptionSection
                        .disabled(!canEdit)
                    finishedSection
                        .disabled(!canEdit)
                    collapsible(.material, title: String(localized: "Material"), summary: materialSummary) {
                        materialSection
                    }
                    collapsible(.time, title: String(localized: "Time on this job"), summary: timeSummary) {
                        timeSection
                    }
                    collapsible(.photos, title: String(localized: "Photos"), summary: photoSummary) {
                        photoSection
                    }
                    collapsible(.signature, title: String(localized: "Client's signature"), summary: signatureSummary) {
                        signatureSection
                    }
                    if job != nil {
                        statusSection
                            .disabled(!canEdit)
                    }
                }
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.large)
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
        .confirmationDialog("Delete this extra work?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: deleteJob)
        } message: {
            Text("Its material, hours, photos and signature are deleted with it.")
        }
    }

    // MARK: - What was done

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            SectionHeading("What was done")
            TextField(String(localized: "e.g. Emergency lighting, stairwell"), text: $draft.description, axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.medium)
                .frame(minHeight: 48)
                .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
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
                        Text("Finished jobs go in the Extra-work report.")
                    } else {
                        Text("In progress until you tick it.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .tint(Color.hoursPositive)
        .frame(minHeight: 44)
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .accessibilityIdentifier("extra-work-finished")
    }

    // MARK: - Material

    private var materialSection: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
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
        HStack(spacing: Metrics.medium) {
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
        .padding(.vertical, Metrics.medium)
    }

    private var suggestions: [ExtraWorkCatalogItem] {
        Array(ExtraWorkCatalog.suggestions(from: catalog, excluding: draft.items.map(\.name)).prefix(8))
    }

    // MARK: - Time on this job

    /// "It took us an hour": one time for the job, however many were on it,
    /// and who was. Saved as each chosen person with that same time, in the
    /// job's existing hours list (`ExtraWorkJob.settingTime`).
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHours {
                timeStepper
                    .padding(.leading, Metrics.large)
                    .padding(.trailing, Metrics.medium)
                    .padding(.vertical, Metrics.small)
                Divider().padding(.leading, Metrics.large)
                whoSection
                    .padding(.horizontal, Metrics.large)
                    .padding(.vertical, Metrics.medium)
                Divider().padding(.leading, Metrics.large)
            }
            HStack(spacing: Metrics.medium) {
                Text("Optional — leave it out when the material says it all")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
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
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .frame(minHeight: 44)
                .accessibilityIdentifier("extra-work-hours-toggle")
            }
            .padding(.horizontal, Metrics.large)
            .padding(.vertical, Metrics.medium)
        }
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
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
    }

    /// One −/+ for the whole job, a quarter of an hour a step; the number
    /// can be tapped to type a time.
    private var timeStepper: some View {
        HStack(spacing: Metrics.medium) {
            Text("How long it took")
                .font(.body)
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
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 64, minHeight: 44)
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

    /// The day's crew as chips to tick: everyone ticked present that day is
    /// chosen when the time is added.
    private var whoSection: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text("Who was on it")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if people.isEmpty {
                Text("Nobody is ticked present on this day.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ExtraWorkFlow(spacing: Metrics.small) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                        personChip(person)
                            .accessibilityIdentifier("extra-work-person-\(index)")
                    }
                }
            }
        }
    }

    private func personChip(_ person: ExtraWorkPerson) -> some View {
        let isChosen = chosen.contains(person.id)
        return Button {
            if isChosen { chosen.remove(person.id) } else { chosen.insert(person.id) }
            applyTime()
        } label: {
            HStack(spacing: Metrics.tiny) {
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(verbatim: person.name)
                    .font(.subheadline)
            }
            .foregroundStyle(isChosen ? Color.white : Color.primary)
            .padding(.horizontal, Metrics.medium)
            .frame(minHeight: 36)
            .background {
                if isChosen {
                    Capsule().fill(Color.accentColor)
                } else {
                    Capsule().strokeBorder(Color.hoursHairline, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
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

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            ExtraWorkFlow(spacing: Metrics.small) {
                ForEach(stored.filter { !removedPhotoIDs.contains($0.id) }) { photo in
                    thumbnail(photo.image, photo: ViewedPhoto(reference: PhotoReference(id: photo.id, isPending: false), data: photo.data))
                }
                ForEach(pending) { photo in
                    thumbnail(photo.image, photo: ViewedPhoto(reference: PhotoReference(id: photo.id, isPending: true), data: photo.data))
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
        // A tap on a photo shows it; removing it is a button in there, with
        // a confirmation. Removing waits for Save, like everything here.
        .sheet(item: $viewing) { photo in
            PhotoViewerSheet(
                data: photo.data,
                spokenName: String(localized: "Extra work photo"),
                onRemove: canEdit ? { removePhoto(photo.reference) } : nil
            )
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

    private func addTile(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(Color.accentColor)
            .frame(width: 84, height: 84)
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
                    .strokeBorder(Color.hoursHairline, style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .contentShape(Rectangle())
    }

    // MARK: - Client's signature

    private var signatureSection: some View {
        HStack(spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: 2) {
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

    /// A section that opens in place under its header. The identifier is on
    /// the header's button, never on this container, which holds buttons.
    private func collapsible<Content: View>(
        _ section: EditorSection,
        title: String,
        summary: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            DisclosureHeader(title: title, summary: summary, isExpanded: expanded.contains(section)) {
                withAnimation(.snappy(duration: 0.25)) {
                    if expanded.contains(section) {
                        expanded.remove(section)
                    } else {
                        expanded.insert(section)
                    }
                }
            }
            .accessibilityIdentifier("extra-work-section-\(section.rawValue)")
            .padding(.horizontal, Metrics.tiny)
            if expanded.contains(section) {
                content()
                    .disabled(!canEdit)
                    .transition(.opacity)
            }
        }
    }

    /// "Items: 3"; nothing when there are none.
    private var materialSummary: String {
        guard !draft.items.isEmpty else { return "" }
        return String(localized: "Items: \(draft.items.count)", comment: "Extra work editor: how many lines of material a job has, on its closed Material section")
    }

    /// "1h · 2 people"; nothing when no time is noted.
    private var timeSummary: String {
        guard showsHours, draft.hasHours else { return "" }
        let count = draft.people.count
        let who = String(inflected: "^[\(count) person](inflect: true)")
        let time = settingsStore.settings.displayFormatting.string(draft.duration)
        return "\(time) · \(who)"
    }

    /// "Photos: 2"; nothing without any.
    private var photoSummary: String {
        photoCount > 0 ? String(localized: "Photos: \(photoCount)", comment: "Extra work job: how many photos it has") : ""
    }

    /// "Signed by Ing. Horvat · 22 Oct", or "Not signed".
    private var signatureSummary: String {
        guard let signature = draft.clientSignature else { return String(localized: "Not signed") }
        return signedLine(signature)
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
            repository.recordUse(of: cleaned.items)
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
