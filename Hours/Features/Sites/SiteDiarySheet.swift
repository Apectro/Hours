import SwiftUI
import SwiftData
import PhotosUI

/// One day's site diary (Bautagebuch), 1.2 redesign, mockup 08 "The day's
/// diary": the weather as chips with the temperature beside them, the four
/// texts as labelled fields, and up to six photos with "+ Photo".
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
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.medium) {
                    SiteCaption(text: String(localized: "Weather"))
                    weatherChips

                    field(.diaryWorkDone, text: $draft.workDone, identifier: "site-diary-work")
                    field(.diaryDeliveries, text: $draft.deliveries, identifier: "site-diary-deliveries")
                    field(.diaryProblems, text: $draft.problems, identifier: "site-diary-problems")
                    field(.diaryVisitors, text: $draft.visitors, identifier: "site-diary-visitors")

                    SiteCaption(text: String(
                        localized: "Photos · \(photos.count) of \(SiteDiary.maximumPhotos)",
                        comment: "Above a day's diary photos; the values are how many there are and the most a day keeps"
                    ))
                    photoGrid
                }
                .padding(Metrics.large)
            }
            .background(Color.hoursCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text(String(
                localized: "Diary · \(settingsStore.dateFormatting.dayTitle(date))",
                comment: "Title of one day's site diary; the value is the date"
            )))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen-site-diary-day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("site-diary-cancel")
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            commit()
                            dismiss()
                        }
                        .fontWeight(.semibold)
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
            HStack(spacing: 2) {
                TextField(String(localized: "Temperature"), text: $temperatureText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .font(.footnote.monospacedDigit())
                    .frame(minWidth: 28, maxWidth: 64)
                    .disabled(!canEdit)
                    .accessibilityLabel(String(localized: "Temperature in degrees Celsius"))
                    .accessibilityIdentifier("site-diary-temperature")
                Text(verbatim: "°C")
                    .font(.footnote)
                    .foregroundStyle(.hoursSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Metrics.medium)
            .frame(minHeight: 44)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.hoursHairlineStyle, lineWidth: 1.5)
            }
        }
    }

    // MARK: - Texts

    private func field(_ term: ExportTerm, text: Binding<String>, identifier: String) -> some View {
        let label = SiteDiary.label(for: term)
        return VStack(alignment: .leading, spacing: Metrics.tiny) {
            Text(verbatim: label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.hoursSecondaryText)
                .accessibilityHidden(true)
            TextField(label, text: text, axis: .vertical)
                .lineLimit(2...6)
                .disabled(!canEdit)
                .frame(minHeight: 44, alignment: .topLeading)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, Metrics.medium + 2)
        .padding(.vertical, Metrics.small + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Photos

    private var slotsLeft: Int { SiteDiary.photoSlotsLeft(existing: photos.count) }

    private var photoGrid: some View {
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
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(
                    localized: "Photo \(index + 1) of \(photos.count)",
                    comment: "VoiceOver, a photo in the site diary; the values are its position and how many there are"
                ))
                .accessibilityIdentifier("site-diary-photo-\(index)")
            }

            if canEdit, slotsLeft > 0 {
                PhotosPicker(selection: $pickedItems, maxSelectionCount: slotsLeft, matching: .images) {
                    addTile(title: String(localized: "Add photo"), systemImage: "plus", isWorking: isAddingPhotos)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Add photos"))
                .accessibilityIdentifier("site-diary-add-photos")

                if CameraPicker.isAvailable {
                    Button {
                        showsCamera = true
                    } label: {
                        addTile(title: String(localized: "Take photo"), systemImage: "camera", isWorking: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("site-diary-camera")
                }
            }
        }
    }

    private func addTile(title: String, systemImage: String, isWorking: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(spacing: Metrics.tiny) {
            if isWorking {
                ProgressView()
            } else {
                Image(systemName: systemImage)
                    .font(.body.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(verbatim: title)
                .font(.footnote.weight(.bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.accentColor)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(Color.hoursSurface, in: shape)
        .overlay { shape.strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])) }
        .contentShape(shape)
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
