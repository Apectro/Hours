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
                Text("Hand the phone to each person. They check their own days and sign with a finger. The signature is printed on the Site sheet.")
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
                    .foregroundStyle(isChanged(person) ? Color.hoursNegative : Color.secondary)
            }
            Spacer(minLength: Metrics.small)
            Text(verbatim: settings.displayFormatting.string(person.minutes))
                .font(.hoursFigure(.body))
            Image(systemName: icon(for: person))
                .foregroundStyle(isChanged(person) ? Color.hoursNegative : Color.secondary)
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

    private func icon(for person: SignOffPerson) -> String {
        switch state(for: person) {
        case .unsigned: return "signature"
        case .signed: return "checkmark.seal.fill"
        case .changedAfterSigning: return "exclamationmark.triangle.fill"
        }
    }

    private func dayRows(for person: SignOffPerson) -> [SignatureSheet.DayRow] {
        let formatting = settingsStore.dateFormatting
        let durations = settings.displayFormatting
        return results
            .sorted { $0.day.date < $1.day.date }
            .compactMap { result in
                guard let entry = result.people.first(where: { $0.memberID == person.id }) else { return nil }
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

    // MARK: - Loading and signing

    private func reload() {
        let calendar = settingsStore.workCalendar
        let siteRepository = SiteRepository(context: modelContext)
        let crew = siteRepository.crew(for: site.id, includeHidden: true)
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        results = siteRepository.siteDays(siteID: site.id, in: month.range(in: calendar)).map { calculator.compute($0) }
        signatures = SiteDiaryRepository(context: modelContext).signatures(siteID: site.id, month: month)

        // You first, then the crew in their order: the sheet's order.
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
        people = list
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
        let calendar = settingsStore.workCalendar
        SiteDiaryRepository(context: modelContext).storeSignature(CrewSignature(
            siteID: site.id,
            memberID: person.id,
            month: month,
            signedOn: CalendarDate.today(in: calendar),
            fingerprint: SignatureFingerprint.make(memberID: person.id, results: results, month: month),
            strokes: strokes,
            aspectRatio: SignatureCanvas.aspectRatio
        ))
        reload()
        onChange()
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

/// One person's month to read, and the line to sign on.
struct SignatureSheet: View {
    struct DayRow: Identifiable, Hashable {
        let id: Int
        let date: String
        let times: String
        let hours: String
    }

    let person: SignOffPerson
    let rows: [DayRow]
    let total: String
    let onSign: ([[SignaturePoint]]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[SignaturePoint]] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        ForEach(rows) { row in
                            HStack {
                                Text(verbatim: row.date)
                                Spacer(minLength: Metrics.small)
                                Text(verbatim: row.times)
                                    .foregroundStyle(.secondary)
                                Text(verbatim: row.hours)
                                    .font(.hoursFigure(.body))
                                    .frame(minWidth: 64, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } footer: {
                        HStack {
                            Text("Total")
                            Spacer()
                            Text(verbatim: total)
                                .font(.hoursFigure(.body))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    }
                }

                // Outside the list, so a stroke is never taken for a scroll.
                VStack(alignment: .leading, spacing: Metrics.small) {
                    HStack {
                        Text(String(
                            localized: "\(person.name), sign to confirm these hours",
                            comment: "Above the signature area; the value is the person's name"
                        ))
                        .font(.subheadline.weight(.semibold))
                        Spacer(minLength: Metrics.small)
                        Button("Clear") { strokes = [] }
                            .disabled(strokes.isEmpty)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("signature-clear")
                    }
                    SignatureCanvas(strokes: $strokes)
                        .accessibilityIdentifier("signature-canvas")
                }
                .padding(Metrics.large)
                .background(Color.hoursCanvas)
            }
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign") {
                        onSign(strokes)
                        dismiss()
                    }
                    .disabled(!CrewSignature.isSignature(strokes))
                    .accessibilityIdentifier("signature-sign")
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
