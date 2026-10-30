import SwiftUI
import SwiftData

/// Crew sign-off for a site's month: everyone who worked it — you first —
/// with their hours and whether they have signed. Each person reads their own
/// days on your phone and signs with a finger.
///
/// A signature keeps a fingerprint of the hours it was given for
/// (`SignatureFingerprint`), so a change afterwards is shown here and on the
/// Site sheet as "changed after signing" rather than passing as signed.
/// Signing again replaces the old signature; removing one asks first, since a
/// signature is the person's word and cannot be given back without them.
///
/// Reached from the export (for the month being exported) and from the site's
/// own menu, where it opens with a month stepper (`latestMonth` set).
///
/// Not under the month lock: crews sign once the month is over, which is when
/// it gets closed, and a signature changes nobody's hours.
struct SiteSignOffScreen: View {
    let site: Site
    /// When set, the month can be stepped, up to this one.
    let latestMonth: YearMonth?
    /// Called after a signature is written or removed, so the export
    /// screen's preview can be drawn again.
    let onChange: () -> Void

    @State private var month: YearMonth
    /// Whose signature is about to be removed, while the question is asked.
    @State private var removing: SignOffPerson?

    init(site: Site, month: YearMonth, latestMonth: YearMonth? = nil, onChange: @escaping () -> Void) {
        self.site = site
        self.latestMonth = latestMonth
        self.onChange = onChange
        _month = State(initialValue: month)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @State private var people: [SignOffPerson] = []
    @State private var results: [SiteDayResult] = []
    @State private var signatures: [CrewSignature] = []
    @State private var signing: SignOffPerson?
    @State private var loaded = false

    var body: some View {
        List {
            if let latestMonth {
                Section {
                    PeriodStepper(
                        month: $month,
                        latest: latestMonth,
                        title: settingsStore.dateFormatting.monthTitle(month),
                        caption: ""
                    )
                }
            }
            Section {
                ForEach(people) { person in
                    Button {
                        signing = person
                    } label: {
                        row(person)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("sign-off-person-\(person.id.uuidString)")
                    .swipeActions {
                        if SignOff.latest(for: person.id, in: signatures, month: month) != nil {
                            Button("Remove signature", role: .destructive) {
                                removing = person
                            }
                        }
                    }
                }
            } footer: {
                Text("Hand the phone to each person. They check their own days and sign with a finger. The signature is printed on the site sheet.")
            }
        }
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { person in
            Button("Remove signature", role: .destructive) {
                removeSignature(of: person)
            }
            .accessibilityIdentifier("sign-off-remove-confirm")
            Button("Cancel", role: .cancel) { removing = nil }
        }
        .overlay {
            if loaded && people.isEmpty {
                ContentUnavailableView(
                    "Nobody to sign",
                    systemImage: "signature",
                    description: Text("Nobody has hours on this site this month.")
                )
            }
        }
        .navigationTitle(String(
            localized: "Sign-off · \(settingsStore.dateFormatting.monthTitle(month))",
            comment: "Title of the crew sign-off screen; the value is a month"
        ))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen-sign-off")
        .task { reload() }
        .onChange(of: month) { _, _ in reload() }
        .sheet(item: $signing) { person in
            SignatureSheet(
                person: person,
                siteName: site.name,
                monthName: settingsStore.dateFormatting.monthName(month),
                rows: dayRows(for: person),
                total: settings.displayFormatting.string(person.minutes),
                onSign: { strokes in sign(person, strokes: strokes) }
            )
        }
    }

    private func row(_ person: SignOffPerson) -> some View {
        HStack(spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: person.name)
                    .font(.body.weight(.semibold))
                Text(verbatim: statusText(for: person))
                    .font(.footnote)
                    .foregroundStyle(isChanged(person) ? Color.hoursAttention : Color.secondary)
            }
            Spacer(minLength: Metrics.small)
            Text(verbatim: settings.displayFormatting.string(person.minutes))
                .font(.hoursFigure(.body))
            Image(systemName: icon(for: person))
                .foregroundStyle(iconColour(for: person))
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }

    /// "Remove Ivan's signature for October 2026?"
    private var removalTitle: String {
        guard let removing else { return "" }
        return String(
            localized: "Remove the signature of \(removing.name) for \(settingsStore.dateFormatting.monthTitle(month))?",
            comment: "Asked before a crew member's signature is removed; the values are their name and a month"
        )
    }

    private func state(for person: SignOffPerson) -> SignOffState {
        SignOff.state(for: person.id, signatures: signatures, results: results, month: month, siteID: site.id)
    }

    private func isChanged(_ person: SignOffPerson) -> Bool {
        if case .changedAfterSigning = state(for: person) { return true }
        return false
    }

    private func statusText(for person: SignOffPerson) -> String {
        let formatting = settingsStore.dateFormatting
        switch state(for: person) {
        case .unsigned:
            return String(localized: "Not signed")
        case let .signed(date):
            return String(
                localized: "Signed \(formatting.dateWithYear(date))",
                comment: "Crew sign-off: when the person signed; the value is a date"
            )
        case let .changedAfterSigning(date):
            return String(
                localized: "Hours changed after signing on \(formatting.dateWithYear(date))",
                comment: "Crew sign-off: the person's hours changed since they signed; the value is a date"
            )
        }
    }

    /// The colour rule: green signed, orange changed since, grey not yet.
    private func iconColour(for person: SignOffPerson) -> Color {
        switch state(for: person) {
        case .unsigned: return .secondary
        case .signed: return .hoursDone
        case .changedAfterSigning: return .hoursAttention
        }
    }

    private func icon(for person: SignOffPerson) -> String {
        switch state(for: person) {
        case .unsigned: return "signature"
        case .signed: return "checkmark.seal.fill"
        case .changedAfterSigning: return "exclamationmark.triangle.fill"
        }
    }

    private func dayRows(for person: SignOffPerson) -> [SignatureSheet.DayRow] {
        SignOffBook.dayRows(for: person.id, results: results, settingsStore: settingsStore)
    }

    // MARK: - Loading and signing

    private func reload() {
        let book = SignOffBook.load(site: site, month: month, context: modelContext, settingsStore: settingsStore)
        results = book.results
        signatures = book.signatures
        people = book.people
        loaded = true
    }

    private func removeSignature(of person: SignOffPerson) {
        removing = nil
        SiteDiaryRepository(context: modelContext)
            .removeSignature(siteID: site.id, memberID: person.id, month: month)
        reload()
        onChange()
    }

    private func sign(_ person: SignOffPerson, strokes: [[SignaturePoint]]) {
        SignOffBook.sign(person.id, site: site, month: month, results: results, strokes: strokes,
                         context: modelContext, calendar: settingsStore.workCalendar)
        reload()
        onChange()
    }
}

/// What a site's sign-off for a month reads and writes, shared by the
/// sign-off list and one person's month ("Sign the month").
@MainActor
enum SignOffBook {
    struct Loaded {
        var results: [SiteDayResult]
        var signatures: [CrewSignature]
        /// Everyone with hours on the site that month: you first, then the
        /// crew in their order, the sheet's order.
        var people: [SignOffPerson]
    }

    static func load(site: Site, month: YearMonth, context: ModelContext, settingsStore: SettingsStore) -> Loaded {
        let settings = settingsStore.settings
        let calendar = settingsStore.workCalendar
        let siteRepository = SiteRepository(context: context)
        let crew = siteRepository.crew(for: site.id, includeHidden: true)
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let results = siteRepository.siteDays(siteID: site.id, in: month.range(in: calendar)).map { calculator.compute($0) }
        let signatures = SiteDiaryRepository(context: context).signatures(siteID: site.id, month: month)

        var minutes: [UUID: Int] = [:]
        for result in results {
            for person in result.people { minutes[person.memberID, default: 0] += person.workedMinutes }
        }
        var list: [SignOffPerson] = []
        if let mine = minutes[CrewMember.youID] {
            let owner = settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
            list.append(SignOffPerson(id: CrewMember.youID, name: owner.isEmpty ? String(localized: "You") : owner, minutes: mine))
        }
        for member in crew.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            guard let theirs = minutes[member.id] else { continue }
            list.append(SignOffPerson(id: member.id, name: member.name, minutes: theirs))
        }
        return Loaded(results: results, signatures: signatures, people: list)
    }

    static func dayRows(for memberID: UUID, results: [SiteDayResult], settingsStore: SettingsStore) -> [SignatureSheet.DayRow] {
        let formatting = settingsStore.dateFormatting
        let durations = settingsStore.settings.displayFormatting
        return results
            .sorted { $0.day.date < $1.day.date }
            .compactMap { result in
                guard let entry = result.people.first(where: { $0.memberID == memberID }) else { return nil }
                let times: String
                if let start = entry.start, let end = entry.end {
                    times = "\(formatting.time(start, on: result.day.date))–\(formatting.time(end, on: result.day.date))"
                } else if result.day.isBadWeatherStop {
                    times = DayTypeCatalog.standard.definition(for: .badWeather).displayName()
                } else {
                    times = "—"
                }
                return SignatureSheet.DayRow(
                    id: result.day.date.key,
                    date: formatting.mediumDate(result.day.date),
                    times: times,
                    hours: durations.string(entry.workedMinutes)
                )
            }
    }

    static func sign(
        _ memberID: UUID,
        site: Site,
        month: YearMonth,
        results: [SiteDayResult],
        strokes: [[SignaturePoint]],
        context: ModelContext,
        calendar: Calendar
    ) {
        SiteDiaryRepository(context: context).storeSignature(CrewSignature(
            siteID: site.id,
            memberID: memberID,
            month: month,
            signedOn: CalendarDate.today(in: calendar),
            fingerprint: SignatureFingerprint.make(memberID: memberID, results: results, month: month),
            strokes: strokes,
            aspectRatio: SignatureCanvas.aspectRatio
        ))
    }
}

/// One person signs their month on one site, from their month on the crew
/// screen ("Sign the month"). Nothing to sign without hours there.
struct MemberSignOffSheet: View {
    let site: Site
    let memberID: UUID
    let month: YearMonth

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var book: SignOffBook.Loaded?

    var body: some View {
        Group {
            if let book, let person = book.people.first(where: { $0.id == memberID }) {
                SignatureSheet(
                    person: person,
                    siteName: site.name,
                    monthName: settingsStore.dateFormatting.monthName(month),
                    rows: SignOffBook.dayRows(for: memberID, results: book.results, settingsStore: settingsStore),
                    total: settingsStore.settings.displayFormatting.string(person.minutes),
                    onSign: { strokes in
                        SignOffBook.sign(memberID, site: site, month: month, results: book.results, strokes: strokes,
                                         context: modelContext, calendar: settingsStore.workCalendar)
                    }
                )
            } else if book != nil {
                NavigationStack {
                    ContentUnavailableView(
                        "Nobody to sign",
                        systemImage: "signature",
                        description: Text("Nobody has hours on this site this month.")
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            book = SignOffBook.load(site: site, month: month, context: modelContext, settingsStore: settingsStore)
        }
    }
}

/// Crew sign-off as a sheet of its own, from the site's menu: on site at the
/// end of the month, nobody should have to go through the export to get
/// people to sign. Opens on `SignOff.defaultMonth`, with a stepper.
struct SiteSignOffSheet: View {
    let site: Site

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        let today = CalendarDate.today(in: settingsStore.workCalendar)
        NavigationStack {
            SiteSignOffScreen(
                site: site,
                month: SignOff.defaultMonth(today: today),
                latestMonth: today.yearMonth,
                onChange: {}
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("sign-off-done")
                }
            }
        }
    }
}

/// Someone on the sign-off list.
struct SignOffPerson: Identifiable, Hashable {
    let id: UUID
    let name: String
    let minutes: Int
}

/// One person's month on a site, to check and sign (1.2, mockup Crew):
/// "Ivan · October" in the bar, the total on the site, "Hand the phone to
/// Ivan…", their days folded under it, the area to sign in, and Clear and
/// Sign at the bottom.
struct SignatureSheet: View {
    struct DayRow: Identifiable, Hashable {
        let id: Int
        let date: String
        let times: String
        let hours: String
    }

    let person: SignOffPerson
    var siteName: String = ""
    var monthName: String = ""
    let rows: [DayRow]
    let total: String
    let onSign: ([[SignaturePoint]]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var strokes: [[SignaturePoint]] = []
    @State private var showsDays = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.medium) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(siteName.isEmpty
                                ? String(localized: "Total")
                                : String(localized: "Total on \(siteName)", comment: "Sign-off: the person's hours on the site; the value is the site's name"))
                            Spacer(minLength: Metrics.small)
                            Text(verbatim: total)
                                .font(.hoursFigure(.title2, weight: .heavy))
                        }
                        .padding(Metrics.large)
                        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                        .accessibilityElement(children: .combine)

                        Text(String(
                            localized: "Hand the phone to \(person.name). They sign that these hours are right.",
                            comment: "Sign-off, above the signature area; the value is the person's name"
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                        DisclosureGroup(isExpanded: $showsDays) {
                            VStack(spacing: Metrics.small) {
                                ForEach(rows) { row in
                                    HStack {
                                        Text(verbatim: row.date)
                                        Spacer(minLength: Metrics.small)
                                        Text(verbatim: row.times)
                                            .foregroundStyle(.hoursSecondaryText)
                                        Text(verbatim: row.hours)
                                            .font(.hoursFigure(.body))
                                            .frame(minWidth: 64, alignment: .trailing)
                                    }
                                    .font(.subheadline)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            .padding(.top, Metrics.small)
                        } label: {
                            Text(String(inflected: "^[\(rows.count) day](inflect: true)"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityIdentifier("signature-days")
                    }
                    .padding(.horizontal, Metrics.large)
                    .padding(.top, Metrics.small)
                }

                // Outside the scroll view, so a stroke is never taken for a
                // scroll.
                SignatureCanvas(strokes: $strokes)
                    .overlay(alignment: .bottomLeading) {
                        Text("Sign here")
                            .font(.caption)
                            .foregroundStyle(.hoursSecondaryText)
                            .padding(.leading, Metrics.large)
                            .padding(.bottom, Metrics.tiny)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    .accessibilityIdentifier("signature-canvas")
                    .padding(.horizontal, Metrics.large)

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Metrics.small))
                    : AnyLayout(HStackLayout(spacing: Metrics.small))
                layout {
                    Button {
                        strokes = []
                    } label: {
                        Text("Clear")
                    }
                    .buttonStyle(.bigAction(.secondary))
                    .disabled(strokes.isEmpty)
                    .accessibilityIdentifier("signature-clear")

                    Button {
                        onSign(strokes)
                        dismiss()
                    } label: {
                        Text("Sign")
                    }
                    .buttonStyle(.bigAction(.primary))
                    .disabled(!CrewSignature.isSignature(strokes))
                    .accessibilityIdentifier("signature-sign")
                }
                .padding(.horizontal, Metrics.large)
                .padding(.bottom, Metrics.small)
            }
            .background(Color.hoursCanvas)
            .navigationTitle(monthName.isEmpty ? person.name : "\(person.name) · \(monthName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("signature-cancel")
                }
            }
        }
        // A downward stroke must not close the sheet halfway through a name.
        .interactiveDismissDisabled()
    }
}

/// A box to sign in with a finger. Strokes are kept as points in a box one
/// unit high (see `SignaturePoint`), so they print sharp at any size.
struct SignatureCanvas: View {
    /// Width over height, fixed so every signature has the same box.
    static let aspectRatio: Double = 3

    @Binding var strokes: [[SignaturePoint]]
    @State private var current: [SignaturePoint] = []

    var body: some View {
        GeometryReader { geometry in
            let height = max(geometry.size.height, 1)
            Canvas { context, _ in
                var path = Path()
                for stroke in strokes + [current] {
                    guard let first = stroke.first else { continue }
                    path.move(to: CGPoint(x: CGFloat(first.x) * height, y: CGFloat(first.y) * height))
                    for point in stroke.dropFirst() {
                        path.addLine(to: CGPoint(x: CGFloat(point.x) * height, y: CGFloat(point.y) * height))
                    }
                }
                context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        current.append(point(value.location, height: height))
                    }
                    .onEnded { _ in
                        if !current.isEmpty { strokes.append(current) }
                        current = []
                    }
            )
        }
        .aspectRatio(CGFloat(SignatureCanvas.aspectRatio), contentMode: .fit)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hoursHairline)
                .frame(height: 1)
                .padding(.horizontal, Metrics.large)
                .padding(.bottom, Metrics.large)
                .allowsHitTesting(false)
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Signature area"))
        .accessibilityHint(String(localized: "Sign with a finger."))
    }

    private func point(_ location: CGPoint, height: CGFloat) -> SignaturePoint {
        SignaturePoint(
            x: min(max(Double(location.x / height), 0), SignatureCanvas.aspectRatio),
            y: min(max(Double(location.y / height), 0), 1)
        )
    }
}
