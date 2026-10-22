import SwiftUI
import SwiftData
import PhotosUI

/// The selected day's site diary (Bautagebuch), under its hours: the
/// weather, four short texts and up to six photos.
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
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case temperature, workDone, deliveries, problems, visitors
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
            Text("Site diary")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            weatherRow

            diaryField(.diaryWorkDone, text: $draft.workDone, field: .workDone, identifier: "site-diary-work")
            diaryField(.diaryDeliveries, text: $draft.deliveries, field: .deliveries, identifier: "site-diary-deliveries")
            diaryField(.diaryProblems, text: $draft.problems, field: .problems, identifier: "site-diary-problems")
            diaryField(.diaryVisitors, text: $draft.visitors, field: .visitors, identifier: "site-diary-visitors")

            photoSection

            Text("Printed after the hours on the director's sheet when you choose to include it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
            DiaryPhotoViewer(photo: photo, canRemove: canEdit) {
                remove(photo)
            }
        }
    }

    // MARK: - Weather

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

    private func diaryField(_ term: ExportTerm, text: Binding<String>, field: Field, identifier: String) -> some View {
        let label = SiteDiary.label(for: term)
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: text, axis: .vertical)
                .lineLimit(1...6)
                .focused($focused, equals: field)
                .disabled(!canEdit)
                .frame(minHeight: 44)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
    }

    // MARK: - Photos

    private var slotsLeft: Int { SiteDiary.photoSlotsLeft(existing: photos.count) }

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

/// One diary photo, large, with a way to remove it.
private struct DiaryPhotoViewer: View {
    let photo: DiaryThumbnail
    let canRemove: Bool
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmsRemoval = false

    var body: some View {
        NavigationStack {
            Group {
                if let image = UIImage(data: photo.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(String(localized: "Site diary photo"))
                } else {
                    Color.hoursCanvas
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hoursCanvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if canRemove {
                    ToolbarItem(placement: .destructiveAction) {
                        Button(role: .destructive) {
                            confirmsRemoval = true
                        } label: {
                            Label("Remove photo", systemImage: "trash")
                        }
                        .accessibilityIdentifier("site-diary-remove-photo")
                    }
                }
            }
            .confirmationDialog("Remove this photo?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Remove photo", role: .destructive, action: onRemove)
            }
        }
    }
}
