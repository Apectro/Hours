import SwiftUI
import SwiftData
import PhotosUI

/// The selected day's site diary (Bautagebuch), under its hours: the
/// weather, four short texts and up to six photos.
///
/// Each part is a row that opens in place, so the card is short when it is
/// not being written: closed, a row shows its title and, when it has
/// something in it, one grey line of it ("Rain, 8 °C", a text's first line,
/// "Photos: 3"). Opening a text row puts the cursor in its field. A row the
/// user opened stays open while the card is on screen; the card is built
/// anew for each date, so a new day starts with every row closed. Closing a
/// row only hides it — nothing typed is lost.
///
/// Saved as it is written, like the day above it: a pick at once, typing when
/// the field is left, and anything pending when the day changes or the screen
/// goes. A diary with nothing in it is not stored. It does not depend on the
/// hours being written, and is not under the month lock — none of it is
/// hours (see `SiteDiaryRepository`) — so only a read-only site stops it.
///
/// Built anew for each date (the screen gives it the date as its identity),
/// so a draft can never be written onto the wrong day.
struct SiteDiaryCard: View {
    let siteID: UUID
    let date: CalendarDate
    let canEdit: Bool
    /// Called after anything is written, so the month grid can mark the day.
    let onChange: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var draft: SiteDiary
    @State private var stored: SiteDiary?
    @State private var temperatureText = ""
    @State private var photos: [DiaryThumbnail] = []
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var isAddingPhotos = false
    @State private var viewing: DiaryThumbnail?
    @State private var expanded: Set<DiaryRow> = []
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case temperature, workDone, deliveries, problems, visitors
    }

    /// The rows that open in place, in their order on the card.
    private enum DiaryRow: String, Hashable {
        case weather, work, deliveries, problems, visitors, photos
    }

    init(siteID: UUID, date: CalendarDate, canEdit: Bool, onChange: @escaping () -> Void) {
        self.siteID = siteID
        self.date = date
        self.canEdit = canEdit
        self.onChange = onChange
        _draft = State(initialValue: SiteDiary(siteID: siteID, date: date))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            // Says up front how it differs from the day's note above: the
            // note is one line in the hours, the diary is pages of its own.
            VStack(alignment: .leading, spacing: 2) {
                Text("Site diary")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Weather, work, photos. Printed on its own pages with the site sheet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 0) {
                weatherSection
                Divider()
                textSection(.work, term: .diaryWorkDone, text: $draft.workDone, field: .workDone, identifier: "site-diary-work")
                Divider()
                textSection(.deliveries, term: .diaryDeliveries, text: $draft.deliveries, field: .deliveries, identifier: "site-diary-deliveries")
                Divider()
                textSection(.problems, term: .diaryProblems, text: $draft.problems, field: .problems, identifier: "site-diary-problems")
                Divider()
                textSection(.visitors, term: .diaryVisitors, text: $draft.visitors, field: .visitors, identifier: "site-diary-visitors")
                Divider()
                photoRow
            }
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .onAppear(perform: load)
        .onDisappear(perform: commit)
        .onChange(of: focused) { old, new in
            if old != nil, old != new { commit() }
        }
        .onChange(of: pickedItems) { _, items in addPicked(items) }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(onPicked: addCameraPhoto)
                .ignoresSafeArea()
        }
        .sheet(item: $viewing) { photo in
            PhotoViewerSheet(
                data: photo.data,
                spokenName: String(localized: "Site diary photo"),
                onRemove: canEdit ? { remove(photo) } : nil
            )
        }
    }

    // MARK: - Rows that open in place

    private func header(_ section: DiaryRow, title: String, summary: String, focus field: Field? = nil) -> some View {
        DisclosureHeader(title: title, summary: summary, isExpanded: expanded.contains(section)) {
            toggle(section, focus: field)
        }
        .accessibilityIdentifier("diary-section-\(section.rawValue)")
    }

    /// Opens or closes a row. Opening a text row puts the cursor in it, when
    /// it can be written; closing one writes what was typed.
    private func toggle(_ section: DiaryRow, focus field: Field?) {
        if expanded.contains(section) {
            if let field, focused == field { focused = nil }
            withAnimation(.snappy(duration: 0.25)) { _ = expanded.remove(section) }
        } else {
            withAnimation(.snappy(duration: 0.25)) { _ = expanded.insert(section) }
            // The field exists from the next pass of the layout, so the
            // cursor is put in it then.
            if canEdit, let field {
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    focused = field
                }
            }
        }
    }

    // MARK: - Weather

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(.weather, title: String(localized: "Weather"), summary: weatherSummary)
            if expanded.contains(.weather) {
                weatherRow
                    .padding(.bottom, Metrics.small)
            }
        }
    }

    /// What was picked and typed, the temperature as typed until it is read.
    private var weatherSummary: String {
        var shown = draft
        shown.temperatureCelsius = SiteDiary.temperature(from: temperatureText)
        return shown.weatherPreview()
    }

    private var weatherRow: some View {
        HStack(spacing: Metrics.medium) {
            Picker(selection: weatherBinding) {
                Text("No weather").tag(DiaryWeather?.none)
                ForEach(DiaryWeather.allCases, id: \.self) { weather in
                    Label(weather.displayName(), systemImage: weather.symbolName)
                        .tag(DiaryWeather?.some(weather))
                }
            } label: {
                Text("Weather")
            }
            .pickerStyle(.menu)
            .disabled(!canEdit)
            .frame(minHeight: 44)
            .accessibilityIdentifier("site-diary-weather")

            Spacer(minLength: Metrics.small)

            HStack(spacing: Metrics.tiny) {
                TextField(String(localized: "Temperature"), text: $temperatureText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .focused($focused, equals: .temperature)
                    .submitLabel(.done)
                    .frame(minWidth: 44, maxWidth: 120, minHeight: 44)
                    .disabled(!canEdit)
                    .accessibilityLabel(String(localized: "Temperature in degrees Celsius"))
                    .accessibilityIdentifier("site-diary-temperature")
                Text(verbatim: "°C")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private var weatherBinding: Binding<DiaryWeather?> {
        Binding(
            get: { draft.weather },
            set: { picked in
                draft.weather = picked
                commit()
            }
        )
    }

    // MARK: - Texts

    private func textSection(_ section: DiaryRow, term: ExportTerm, text: Binding<String>, field: Field, identifier: String) -> some View {
        let label = SiteDiary.label(for: term)
        return VStack(alignment: .leading, spacing: 0) {
            header(section, title: label, summary: SiteDiary.preview(of: text.wrappedValue), focus: field)
            if expanded.contains(section) {
                TextField(label, text: text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused, equals: field)
                    .disabled(!canEdit)
                    .frame(minHeight: 44)
                    .padding(.bottom, Metrics.small)
                    .accessibilityLabel(label)
                    .accessibilityIdentifier(identifier)
            }
        }
    }

    // MARK: - Photos

    private var slotsLeft: Int { SiteDiary.photoSlotsLeft(existing: photos.count) }

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            header(
                .photos,
                title: String(localized: "Photos"),
                summary: photos.isEmpty
                    ? ""
                    : String(localized: "Photos: \(photos.count)", comment: "Extra work job: how many photos it has")
            )
            if expanded.contains(.photos) {
                photoSection
                    .padding(.bottom, Metrics.small)
            }
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        if !photos.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: Metrics.small)], spacing: Metrics.small) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button {
                        viewing = photo
                    } label: {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 88)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(
                        localized: "Photo \(index + 1) of \(photos.count)",
                        comment: "VoiceOver, a photo in the site diary; the values are its position and how many there are"
                    ))
                    .accessibilityIdentifier("site-diary-photo-\(index)")
                }
            }
        }

        if canEdit {
            if slotsLeft > 0 {
                HStack(spacing: Metrics.medium) {
                    PhotosPicker(selection: $pickedItems, maxSelectionCount: slotsLeft, matching: .images) {
                        Label("Add photos", systemImage: "photo.on.rectangle")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("site-diary-add-photos")

                    if CameraPicker.isAvailable {
                        Button {
                            commit()
                            showsCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera")
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("site-diary-camera")
                    }

                    if isAddingPhotos {
                        ProgressView()
                    }
                }
                .font(.subheadline.weight(.semibold))
            } else {
                Text("Six photos is the most a day keeps.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Loading and writing

    private var repository: SiteDiaryRepository {
        SiteDiaryRepository(context: modelContext)
    }

    /// Read outside `body`: the repository's reads can collapse duplicates,
    /// which writes.
    private func load() {
        stored = repository.diary(siteID: siteID, on: date)
        draft = stored ?? SiteDiary(siteID: siteID, date: date)
        temperatureText = draft.temperatureCelsius.map { "\($0)" } ?? ""
        loadPhotos()
    }

    private func loadPhotos() {
        photos = repository.photos(siteID: siteID, on: date).compactMap { photo in
            guard let image = DiaryPhotoProcessor.thumbnail(from: photo.jpegData, maxPixel: 300) else { return nil }
            return DiaryThumbnail(id: photo.id, image: image, data: photo.jpegData)
        }
    }

    /// The one place the diary is written. The temperature is read from what
    /// was typed; a blank diary removes the stored one.
    private func commit() {
        guard canEdit else { return }
        var next = draft
        next.temperatureCelsius = SiteDiary.temperature(from: temperatureText)
        temperatureText = next.temperatureCelsius.map { "\($0)" } ?? ""
        draft = next
        let unchanged = next == (stored ?? SiteDiary(siteID: siteID, date: date))
        guard !unchanged else { return }
        repository.store(next)
        stored = next.isBlank ? nil : next
        onChange()
    }

    private func addPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        pickedItems = []
        isAddingPhotos = true
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let jpeg = await Task.detached(priority: .userInitiated) {
                    DiaryPhotoProcessor.storedJPEG(from: data)
                }.value
                if let jpeg { repository.addPhoto(jpeg, siteID: siteID, on: date) }
            }
            isAddingPhotos = false
            loadPhotos()
            onChange()
        }
    }

    private func addCameraPhoto(_ image: UIImage) {
        guard let jpeg = DiaryPhotoProcessor.storedJPEG(from: image) else { return }
        repository.addPhoto(jpeg, siteID: siteID, on: date)
        loadPhotos()
        onChange()
    }

    private func remove(_ photo: DiaryThumbnail) {
        repository.removePhoto(id: photo.id)
        viewing = nil
        loadPhotos()
        onChange()
    }
}

/// A diary photo ready for the screen.
struct DiaryThumbnail: Identifiable {
    let id: UUID
    let image: UIImage
    /// The stored JPEG, for the full-size view.
    let data: Data
}
