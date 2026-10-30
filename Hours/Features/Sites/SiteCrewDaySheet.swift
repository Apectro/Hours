import SwiftUI

/// "Something's different" (1.2 redesign, mockup 06 phone 2): "Who's
/// different today?", one row per person with what they have now and four
/// buttons — Usual · Late/early · Away · Moved — and the day's people and
/// hours on the Save button at the bottom.
///
/// Works on a draft of the day: nothing is written until Save, which hands
/// the whole day back to the site screen, where the month lock and your
/// calendar day are handled. Late/early opens that person's times, Away asks
/// why, and Moved saves what is here first and then opens the move, which
/// writes two sites at once and so cannot wait in a draft.
struct SiteCrewDaySheet: View {
    let title: String
    let initial: SiteDay
    let rows: [PersonReference]
    let dayTypes: DayTypeCatalog
    let otherSites: [Site]
    let siteNames: [UUID: String]
    /// Who was ticked on another of your sites that day, and which: offered
    /// first when they are marked away.
    let elsewhere: [UUID: UUID]
    /// The site's usual times, for someone ticked in on a day with none yet.
    let usualTimes: SiteUsualTimes
    /// The site gives the field allowance to everyone ticked in.
    let allowanceByDefault: Bool
    let onSave: (SiteDay) -> Void
    /// Saves the draft and opens the move for one person.
    let onMove: (SiteDay, UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var draft: SiteDay
    @State private var editing: Editing?

    /// One sheet at a time over this one, chosen by value.
    private enum Editing: Identifiable {
        case times(PersonReference)
        case away(PersonReference)

        var id: String {
            switch self {
            case let .times(person): return "times-\(person.id.uuidString)"
            case let .away(person): return "away-\(person.id.uuidString)"
            }
        }
    }

    init(
        title: String,
        initial: SiteDay,
        rows: [PersonReference],
        dayTypes: DayTypeCatalog,
        otherSites: [Site],
        siteNames: [UUID: String],
        elsewhere: [UUID: UUID],
        usualTimes: SiteUsualTimes,
        allowanceByDefault: Bool,
        onSave: @escaping (SiteDay) -> Void,
        onMove: @escaping (SiteDay, UUID) -> Void
    ) {
        self.title = title
        self.initial = initial
        self.rows = rows
        self.dayTypes = dayTypes
        self.otherSites = otherSites
        self.siteNames = siteNames
        self.elsewhere = elsewhere
        self.usualTimes = usualTimes
        self.allowanceByDefault = allowanceByDefault
        self.onSave = onSave
        self.onMove = onMove
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.small + 1) {
                    Text("Who's different today?")
                        .font(.title2.weight(.heavy))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, Metrics.tiny)

                    ForEach(rows) { person in
                        row(person)
                    }

                    if rows.contains(where: { state(of: $0).isMoved }) {
                        Text("Someone who moved is changed with Undo on the day, then here.")
                            .font(.footnote)
                            .foregroundStyle(.hoursSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Metrics.small)
                    }
                }
                .padding(.horizontal, Metrics.large)
                .padding(.bottom, Metrics.large)
            }
            .background(Color.hoursCanvas)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("Save") + Text(verbatim: " · \(SiteDayStyle.figures(figures, durations: durations))")
                }
                .buttonStyle(.bigAction(.primary, isMain: true))
                .accessibilityIdentifier("site-different-save")
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.small)
                .background(.bar)
            }
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("site-different")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("site-different-cancel")
                }
            }
            .sheet(item: $editing) { editing in
                switch editing {
                case let .times(person):
                    PersonTimesSheet(
                        name: person.name,
                        attendance: draft.attendance(for: person.id) ?? Attendance(memberID: person.id),
                        day: withTimes(draft),
                        onSave: { attendance in
                            draft = withTimes(draft).settingAttendance(attendance, allowanceByDefault: allowanceByDefault)
                        }
                    )
                case let .away(person):
                    SiteAwaySheet(
                        person: person,
                        date: draft.date,
                        current: draft.absenceReason(for: person.id),
                        hint: elsewhere[person.id],
                        dayTypes: dayTypes,
                        otherSites: otherSites,
                        onPick: { reason in
                            draft = reason.map { draft.settingReason($0, for: person.id) }
                                ?? draft.settingNotHere(for: person.id)
                        }
                    )
                }
            }
        }
        .presentationDetents([.large])
        // A stray swipe must not throw away a day that was changed.
        .interactiveDismissDisabled(draft != initial)
    }

    // MARK: - A person

    private func row(_ person: PersonReference) -> some View {
        let state = state(of: person)
        let key = SiteDayStyle.key(person)
        return VStack(alignment: .leading, spacing: Metrics.small) {
            HStack(spacing: Metrics.small) {
                SiteInitials(person: person, isHere: state.isHere)
                Text(verbatim: person.name)
                    .font(.body)
                Spacer(minLength: Metrics.small)
                Text(verbatim: stateText(person, state))
                    .font(.subheadline.weight(state == .usual || state == .notHere ? .regular : .bold).monospacedDigit())
                    .foregroundStyle(stateColor(state))
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("site-state-\(key)")
            }

            // Two by two at the largest text sizes, rather than four
            // squeezed words.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 5) {
                    HStack(spacing: 5) {
                        usualButton(person, state, key)
                        lateButton(person, state, key)
                    }
                    HStack(spacing: 5) {
                        awayButton(person, state, key)
                        movedButton(person, state, key)
                    }
                }
            } else {
                HStack(spacing: 5) {
                    usualButton(person, state, key)
                    lateButton(person, state, key)
                    awayButton(person, state, key)
                    movedButton(person, state, key)
                }
            }
        }
        .padding(.horizontal, Metrics.medium)
        .padding(.vertical, Metrics.small + 2)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: SiteDayStyle.groupRadius, style: .continuous))
    }

    private func usualButton(_ person: PersonReference, _ state: SiteCrewState, _ key: String) -> some View {
        Button("Usual") {
            draft = withTimes(draft).settingUsual(for: person.id, allowanceByDefault: allowanceByDefault)
        }
        .buttonStyle(SiteChoiceButtonStyle(tint: state == .usual ? .accent : .plain))
        .disabled(state.isMoved)
        .accessibilityAddTraits(state == .usual ? .isSelected : [])
        .accessibilityLabel(Text("Usual") + Text(verbatim: ", \(person.name)"))
        .accessibilityIdentifier("site-usual-\(key)")
    }

    private func lateButton(_ person: PersonReference, _ state: SiteCrewState, _ key: String) -> some View {
        Button("Late/early") { editing = .times(person) }
            .buttonStyle(SiteChoiceButtonStyle(tint: state == .ownTimes ? .attention : .plain))
            .disabled(state.isMoved)
            .accessibilityAddTraits(state == .ownTimes ? .isSelected : [])
            .accessibilityLabel(Text("Late/early") + Text(verbatim: ", \(person.name)"))
            .accessibilityIdentifier("site-late-\(key)")
    }

    private func awayButton(_ person: PersonReference, _ state: SiteCrewState, _ key: String) -> some View {
        Button("Away") { editing = .away(person) }
            .buttonStyle(SiteChoiceButtonStyle(tint: state.isAway ? .attention : .plain))
            .disabled(state.isMoved)
            .accessibilityAddTraits(state.isAway ? .isSelected : [])
            .accessibilityLabel(Text("Away") + Text(verbatim: ", \(person.name)"))
            .accessibilityIdentifier("site-away-\(key)")
    }

    private func movedButton(_ person: PersonReference, _ state: SiteCrewState, _ key: String) -> some View {
        Button("Moved") {
            let ticked = state.isHere ? draft : withTimes(draft).settingUsual(for: person.id, allowanceByDefault: allowanceByDefault)
            onMove(ticked, person.id)
        }
        .buttonStyle(SiteChoiceButtonStyle(tint: state.isMoved ? .accent : .plain))
        // Somewhere to go, and times to leave from.
        .disabled(state.isMoved || otherSites.isEmpty || withTimes(draft).start == nil || withTimes(draft).end == nil)
        .accessibilityAddTraits(state.isMoved ? .isSelected : [])
        .accessibilityLabel(Text("Moved") + Text(verbatim: ", \(person.name)"))
        .accessibilityIdentifier("site-moved-\(key)")
    }

    // MARK: - Derived

    private var durations: DurationFormatting { settingsStore.settings.displayFormatting }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }

    private var figures: SiteCrewFigures {
        let calculator = SiteDayCalculator(settings: settingsStore.settings, calendar: settingsStore.workCalendar)
        return SiteCrewFigures(calculator.compute(draft).people)
    }

    private func state(of person: PersonReference) -> SiteCrewState {
        SiteCrewState.of(person.id, in: draft)
    }

    /// The draft with the site's usual times, when it has none yet and is
    /// not a day the weather stopped before anyone started: what someone
    /// ticked in on a bare day starts with.
    private func withTimes(_ day: SiteDay) -> SiteDay {
        guard day.start == nil, day.end == nil, !day.isBadWeatherStop else { return day }
        var next = day
        next.start = usualTimes.start
        next.end = usualTimes.end
        next.breakMinutes = usualTimes.breakMinutes
        return next
    }

    /// What the row says on the right: their times, why they were away, or
    /// where they went.
    private func stateText(_ person: PersonReference, _ state: SiteCrewState) -> String {
        switch state {
        case .usual, .ownTimes:
            let mine = draft.resolved(for: person.id)
            return SiteDayStyle.range(mine?.start, mine?.end, on: draft.date, formatting: formatting)
        case let .moved(siteID):
            let site = siteNames[siteID] ?? String(localized: "Another site")
            let left = draft.move(of: person.id).map { formatting.time($0.left, on: draft.date) } ?? ""
            return "→ \(site) \(left)"
        case let .away(reason):
            return SiteAwaySheet.title(of: reason, dayTypes: dayTypes, siteNames: siteNames)
        case .notHere:
            return String(localized: "Not here")
        }
    }

    private func stateColor(_ state: SiteCrewState) -> Color {
        switch state {
        case .usual: return .secondary
        case .ownTimes, .away: return .hoursAttention
        case .moved: return .accentColor
        case .notHere: return .secondary
        }
    }

    private func save() {
        onSave(draft)
        dismiss()
    }
}

private extension SiteCrewState {
    var isMoved: Bool {
        if case .moved = self { return true }
        return false
    }

    var isAway: Bool {
        if case .away = self { return true }
        return false
    }
}

/// "Why wasn't Ivan here?" (mockup 06 phone 4): the day types that mean
/// away as big buttons, "On another site…", and "Unpaid / no reason". A tap
/// is the answer; the sheet closes.
struct SiteAwaySheet: View {
    let person: PersonReference
    let date: CalendarDate
    let current: AbsenceReason?
    /// The other site they were ticked on that day, offered first.
    let hint: UUID?
    let dayTypes: DayTypeCatalog
    let otherSites: [Site]
    /// The reason, or nil for none.
    let onPick: (AbsenceReason?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.small) {
                    Text(String(
                        localized: "Why wasn't \(person.name) here?",
                        comment: "Title of the reasons someone was away from the site; the value is their name"
                    ))
                    .font(.title2.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, Metrics.tiny)

                    if let hint, let site = otherSites.first(where: { $0.id == hint }) {
                        reasonButton(
                            title: String(localized: "At \(site.name)", comment: "A crew row: working on another site that day; the value is its name"),
                            color: .accentColor,
                            isChosen: current == .otherSite(hint),
                            identifier: "site-absence-hint"
                        ) { pick(.otherSite(hint)) }
                    }

                    ForEach(dayTypes.absenceReasons) { option in
                        reasonButton(
                            title: option.displayName(),
                            color: option.tint.color,
                            isChosen: current == .dayType(option.id),
                            identifier: "site-absence-reason-\(option.id.rawValue)"
                        ) { pick(.dayType(option.id)) }
                    }

                    otherSiteMenu

                    reasonButton(
                        title: String(localized: "Unpaid / no reason"),
                        color: .gray,
                        isChosen: current == nil,
                        identifier: "site-absence-reason-none"
                    ) { pick(nil) }

                    Text("Shown on the sheet instead of their hours.")
                        .font(.footnote)
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Metrics.small)
                        .padding(.top, Metrics.tiny)
                }
                .padding(.horizontal, Metrics.large)
                .padding(.bottom, Metrics.large)
            }
            .background(Color.hoursCanvas)
            .navigationTitle(Text(verbatim: "\(person.name) · \(settingsStore.dateFormatting.dayTitle(date))"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("site-away")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("site-away-cancel")
                }
            }
        }
        .presentationDetents([.large])
    }

    /// "On another site…": each of your other sites, and "Another site" for
    /// one not in the app.
    private var otherSiteMenu: some View {
        Menu {
            ForEach(Array(otherSites.enumerated()), id: \.element.id) { offset, site in
                Button {
                    pick(.otherSite(site.id))
                } label: {
                    if current == .otherSite(site.id) {
                        Label(site.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: site.name)
                    }
                }
                .accessibilityIdentifier("site-absence-other-site-\(offset)")
            }
            Button {
                pick(.otherSite(nil))
            } label: {
                if current == .otherSite(nil) {
                    Label("Another site", systemImage: "checkmark")
                } else {
                    Text("Another site")
                }
            }
            .accessibilityIdentifier("site-absence-other-site-any")
        } label: {
            reasonLabel(
                title: String(localized: "On another site…"),
                color: .accentColor,
                isChosen: { if case .otherSite? = current { return true } else { return false } }()
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityIdentifier("site-absence-reason-other-site")
    }

    private func reasonButton(title: String, color: Color, isChosen: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            reasonLabel(title: title, color: color, isChosen: isChosen)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func reasonLabel(title: String, color: Color, isChosen: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: SiteDayStyle.groupRadius, style: .continuous)
        return HStack(spacing: Metrics.medium) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.body.weight(.semibold))
                .foregroundStyle(isChosen ? Color.hoursAttention : Color.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Metrics.large)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(isChosen ? Color.hoursAttentionFill.opacity(0.12) : Color.hoursSurface, in: shape)
        .overlay { shape.strokeBorder(isChosen ? Color.hoursAttentionFill : Color(uiColor: .separator), lineWidth: 1.5) }
        .contentShape(shape)
    }

    private func pick(_ reason: AbsenceReason?) {
        onPick(reason)
        dismiss()
    }

    /// A reason as the crew's rows write it: "Sick leave", "At Bau Süd",
    /// "Another site".
    static func title(of reason: AbsenceReason, dayTypes: DayTypeCatalog, siteNames: [UUID: String]) -> String {
        switch reason {
        case let .dayType(id):
            return dayTypes.definition(for: id).displayName()
        case let .otherSite(siteID):
            guard let name = siteID.flatMap({ siteNames[$0] }) else { return String(localized: "Another site") }
            return String(localized: "At \(name)", comment: "A crew row: working on another site that day; the value is its name")
        }
    }
}
