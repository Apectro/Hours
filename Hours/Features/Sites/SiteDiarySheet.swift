import SwiftUI
import SwiftData
import PhotosUI

/// One day's site diary (Bautagebuch), 1.2 redesign, mockup 08 "The day's
/// diary", as a form: the weather as chips and the temperature, the four
/// texts each in its own section, and up to six photos.
///
/// Opened from "Diary for this day" under the day's hours. The weather and
/// the texts are kept on Save and left as they were on Cancel. A photo is
/// stored as soon as it is picked or taken, since a picture someone has just
/// taken is not something to lose to a Cancel; removing one asks first.
///
/// Not under the month lock — none of it is hours (see
/// `SiteDiaryRepository`) — so only a read-only site stops it. A diary with
/// nothing in it is not stored.
struct SiteDiarySheet: View {
    let siteID: UUID
    let date: CalendarDate
    /// The site's name, under a photo.
    let siteName: String
    let canEdit: Bool
    /// Called after anything is written, so the month grid can mark the day.
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @State private var draft: SiteDiary
    @State private var stored: SiteDiary?
    @State private var temperatureText = ""
    @State private var photos: [DiaryThumbnail] = []
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var isAddingPhotos = false
    @State private var viewing: DiaryThumbnail?

    init(siteID: UUID, date: CalendarDate, siteName: String, canEdit: Bool, onChange: @escaping () -> Void) {
        self.siteID = siteID
        self.date = date
        self.siteName = siteName
        self.canEdit = canEdit
        self.onChange = onChange
        _draft = State(initialValue: SiteDiary(siteID: siteID, date: date))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    weatherChips
                    HStack(spacing: Metrics.small) {
                        Text("Temperature")
                        Spacer(minLength: Metrics.small)
                        TextField(String(localized: "Temperature"), text: $temperatureText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(minWidth: 28, maxWidth: 80)
                            .disabled(!canEdit)
                            .accessibilityLabel(String(localized: "Temperature in degrees Celsius"))
                            .accessibilityIdentifier("site-diary-temperature")
                        Text(verbatim: "°C")
                            .foregroundStyle(.hoursSecondaryText)
                            .accessibilityHidden(true)
                    }
                } header: {
                    Text("Weather")
                        .textCase(nil)
                }

                field(.diaryWorkDone, text: $draft.workDone, identifier: "site-diary-work")
                field(.diaryDeliveries, text: $draft.deliveries, identifier: "site-diary-deliveries")
                field(.diaryProblems, text: $draft.problems, identifier: "site-diary-problems")
                field(.diaryVisitors, text: $draft.visitors, identifier: "site-diary-visitors")

                photoSection
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("screen-site-diary-day")
            .navigationTitle(Text(String(
                localized: "Diary · \(settingsStore.dateFormatting.dayTitle(date))",
                comment: "Title of one day's site diary; the value is the date"
            )))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("site-diary-cancel")
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            commit()
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel(String(localized: "Save"))
                        .accessibilityIdentifier("site-diary-save")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(hasChanges)
        .onAppear(perform: load)
        .onChange(of: pickedItems) { _, items in addPicked(items) }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker(onPicked: addCameraPhoto)
                .ignoresSafeArea()
        }
        .sheet(item: $viewing) { photo in
            PhotoViewerSheet(
                data: photo.data,
                spokenName: String(localized: "Site diary photo"),
                onRemove: canEdit ? { remove(photo) } : nil,
                position: photos.firstIndex(where: { $0.id == photo.id }).map { (index: $0 + 1, count: photos.count) },
                caption: "\(settingsStore.dateFormatting.dayTitle(date)) · \(siteName)"
            )
        }
    }

    // MARK: - Weather

    private var weatherChips: some View {
        ExtraWorkFlow(spacing: 6) {
            ForEach(DiaryWeather.allCases, id: \.self) { weather in
                let isOn = draft.weather == weather
                Button {
                    draft.weather = isOn ? nil : weather
                } label: {
                    Label(weather.displayName(), systemImage: weather.symbolName)
                        .labelStyle(.titleOnly)
                }
                .buttonStyle(SiteChoiceButtonStyle(tint: isOn ? .accent : .plain, isCapsule: true))
                .disabled(!canEdit)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("site-diary-weather-\(weather.rawValue)")
            }
        }
        .padding(.vertical, Metrics.tiny)
    }

    // MARK: - Texts

    /// One of the four texts, its name as the section's header.
    private func field(_ term: ExportTerm, text: Binding<String>, identifier: String) -> some View {
        let label = SiteDiary.label(for: term)
        return Section {
            TextField(label, text: text, axis: .vertical)
                .lineLimit(2...6)
                .disabled(!canEdit)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        } header: {
            Text(verbatim: label)
                .textCase(nil)
        }
    }

    // MARK: - Photos

    private var slotsLeft: Int { SiteDiary.photoSlotsLeft(existing: photos.count) }

    /// The photos in a grid row, then Add photos and the camera.
    private var photoSection: some View {
        Section {
            if !photos.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            viewing = photo
                        } label: {
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .frame(height: 84)
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
                .padding(.vertical, Metrics.tiny)
            }

            if canEdit, slotsLeft > 0 {
                HStack(spacing: Metrics.medium) {
                    PhotosPicker(selection: $pickedItems, maxSelectionCount: slotsLeft, matching: .images) {
                        HStack(spacing: Metrics.small) {
                            Text("Add photo")
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
                    .accessibilityIdentifier("site-diary-add-photos")
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
                        .accessibilityIdentifier("site-diary-camera")
                    }
                }
            }
        } header: {
            Text(String(
                localized: "Photos · \(photos.count) of \(SiteDiary.maximumPhotos)",
                comment: "Above a day's diary photos; the values are how many there are and the most a day keeps"
            ))
            .textCase(nil)
        }
    }

    // MARK: - Loading and writing

    private var repository: SiteDiaryRepository {
        SiteDiaryRepository(context: modelContext)
    }

    /// The weather and texts as Save would write them.
    private var proposed: SiteDiary {
        var next = draft
        next.temperatureCelsius = SiteDiary.temperature(from: temperatureText)
        return next
    }

    private var hasChanges: Bool {
        canEdit && proposed != (stored ?? SiteDiary(siteID: siteID, date: date))
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

    /// The one place the weather and texts are written; a blank diary
    /// removes the stored one.
    private func commit() {
        guard hasChanges else { return }
        let next = proposed
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
