import SwiftUI

/// What the move sheet hands back: where, when, the break, and who went.
struct SiteMoveChoice: Hashable {
    var site: Site
    var left: TimeOfDay
    var started: TimeOfDay
    var breakPlacement: BreakPlacement
    var memberIDs: [UUID]
}

/// "Moved to another site" (mockup Move): part of the crew left this site
/// and finished the day on another. To, When, Who went, and a sentence
/// saying what Move will write on both sites.
///
/// Checks the choice with the engine as it changes (`check`), so Move is only
/// offered for one that can be made and the reason is said otherwise; the
/// site screen does the writing.
struct SiteMoveSheet: View {
    let site: Site
    let day: SiteDay
    /// Everyone ticked here who has not already moved, in the card's order.
    let people: [PersonReference]
    /// The other active sites.
    let otherSites: [Site]
    /// When they left, unless changed: `SiteMoving.suggestedLeftTime`.
    let suggestedLeft: TimeOfDay
    /// Whether the choice can be made; nil when it can.
    let check: (SiteMoveChoice) -> SiteMoveError?
    let onMove: (SiteMoveChoice) -> Void
    /// Your running clock, if any (1.2): when you go, it goes with you, and
    /// the summary says so (`ClockFollowsMove`).
    var runningClock: RunningShift? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    @State private var siteID: UUID?
    @State private var left: TimeOfDay
    @State private var started: TimeOfDay
    /// Nil until chosen: then it follows where the break falls in time.
    @State private var chosenPlacement: BreakPlacement?
    @State private var going: Set<UUID>

    init(
        site: Site,
        day: SiteDay,
        people: [PersonReference],
        preselected: Set<UUID>?,
        otherSites: [Site],
        suggestedLeft: TimeOfDay,
        check: @escaping (SiteMoveChoice) -> SiteMoveError?,
        onMove: @escaping (SiteMoveChoice) -> Void,
        runningClock: RunningShift? = nil
    ) {
        self.site = site
        self.day = day
        self.people = people
        self.otherSites = otherSites
        self.suggestedLeft = suggestedLeft
        self.check = check
        self.onMove = onMove
        self.runningClock = runningClock
        _siteID = State(initialValue: otherSites.count == 1 ? otherSites.first?.id : nil)
        _left = State(initialValue: suggestedLeft)
        _started = State(initialValue: suggestedLeft)
        _going = State(initialValue: preselected ?? Set(people.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Array(otherSites.enumerated()), id: \.element.id) { offset, other in
                        Button {
                            siteID = other.id
                        } label: {
                            HStack {
                                Text(verbatim: other.name)
                                    .fontWeight(other.id == siteID ? .semibold : .regular)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if other.id == siteID {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(other.id == siteID ? .isSelected : [])
                        .accessibilityIdentifier("site-move-to-\(offset)")
                    }
                } header: {
                    Text("Went to")
                }

                Section {
                    DatePicker(
                        String(localized: "Left \(site.name)", comment: "Move sheet: the time people left this site; the value is its name"),
                        selection: timeBinding($left, keepsStartedAfter: true),
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityIdentifier("site-move-left")
                    DatePicker(
                        startedTitle,
                        selection: timeBinding($started, keepsStartedAfter: false),
                        displayedComponents: .hourAndMinute
                    )
                    .accessibilityIdentifier("site-move-started")
                    if day.breakMinutes > 0 || people.contains(where: { (day.resolved(for: $0.id)?.breakMinutes ?? 0) > 0 }) {
                        Picker("Break", selection: placementBinding) {
                            Text(placementTitle(.here)).tag(BreakPlacement.here)
                            Text(placementTitle(.there)).tag(BreakPlacement.there)
                            Text("Half on each").tag(BreakPlacement.split)
                        }
                        .accessibilityIdentifier("site-move-break")
                    }
                } header: {
                    Text("When")
                }

                Section {
                    ForEach(people) { person in
                        Button {
                            if going.contains(person.id) { going.remove(person.id) } else { going.insert(person.id) }
                        } label: {
                            HStack {
                                Text(verbatim: person.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if going.contains(person.id) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.accentColor)
                                } else {
                                    Text("stays here")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(going.contains(person.id) ? .isSelected : [])
                        .accessibilityIdentifier(person.id == CrewMember.youID ? "site-move-person-you" : "site-move-person-\(person.name)")
                    }
                } header: {
                    Text("Who went")
                } footer: {
                    Text(verbatim: footer)
                        .accessibilityIdentifier("site-move-summary")
                }
            }
            .navigationTitle("Moved to another site")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("site-move-sheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("site-move-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        guard let choice else { return }
                        onMove(choice)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(choice == nil || problem != nil)
                    .accessibilityIdentifier("site-move-confirm")
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(siteID != nil)
    }

    // MARK: - Derived

    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var target: Site? { otherSites.first { $0.id == siteID } }

    private var startedTitle: String {
        guard let target else { return String(localized: "Started at the other site") }
        return String(localized: "Started at \(target.name)", comment: "Move sheet: the time people started on the other site; the value is its name")
    }

    /// Where the break falls in time, until one is chosen.
    private var placement: BreakPlacement {
        chosenPlacement ?? SiteMoving.defaultBreakPlacement(
            start: day.start, end: day.end, breakMinutes: day.breakMinutes, left: left
        )
    }

    private var placementBinding: Binding<BreakPlacement> {
        Binding(get: { placement }, set: { chosenPlacement = $0 })
    }

    private func placementTitle(_ placement: BreakPlacement) -> String {
        switch placement {
        case .here:
            return String(localized: "At \(site.name)", comment: "A crew row: working on another site that day; the value is its name")
        case .there:
            guard let target else { return String(localized: "At the other site") }
            return String(localized: "At \(target.name)", comment: "A crew row: working on another site that day; the value is its name")
        case .split:
            return String(localized: "Half on each")
        }
    }

    /// Who went, in the card's order.
    private var memberIDs: [UUID] { people.map(\.id).filter(going.contains) }

    private var choice: SiteMoveChoice? {
        guard let target, !memberIDs.isEmpty else { return nil }
        return SiteMoveChoice(site: target, left: left, started: started, breakPlacement: placement, memberIDs: memberIDs)
    }

    private var problem: SiteMoveError? { choice.flatMap(check) }

    /// What Move will write, in one or two sentences, or why it cannot.
    private var footer: String {
        guard let target else { return String(localized: "Choose the site they went to.") }
        guard !memberIDs.isEmpty else { return String(localized: "Tick who went.") }
        if let problem { return message(for: problem) }
        let leftText = formatting.time(left, on: day.date)
        let startedText = formatting.time(started, on: day.date)
        let goingCount = memberIDs.count
        let staying = people.filter { !going.contains($0.id) }
        var sentences = [String(
            localized: "\(site.name) gets their hours until \(leftText) for the \(goingCount) who went. \(target.name) gets them from \(startedText).",
            comment: "Move sheet summary; the values are this site, a time, how many went, the other site and a time"
        )]
        if let end = day.end, !staying.isEmpty {
            let names = staying.map(\.name).joined(separator: ", ")
            sentences.append(String(
                localized: "Staying here until \(formatting.time(end, on: day.date)): \(names).",
                comment: "Move sheet summary; the values are the day's end and the names of who stays"
            ))
        }
        let clockMoves = ClockFollowsMove.handover(
            running: runningClock,
            youMoved: going.contains(CrewMember.youID),
            date: day.date,
            left: left,
            started: started,
            calendar: calendar
        ) != nil
        if clockMoves {
            sentences.append(String(localized: "Your clock moves too."))
        }
        return sentences.joined(separator: " ")
    }

    private func message(for problem: SiteMoveError) -> String {
        switch problem {
        case .leftOutsideShift:
            return String(localized: "They left outside the hours they worked here. Choose a time between their start and their end.")
        case .startedBeforeLeft:
            return String(localized: "They started on the other site before they left this one.")
        case .startedAfterEnd:
            return String(localized: "They started on the other site after their day here ended.")
        case .noTimes:
            return String(localized: "Write this day's start and end first.")
        case .notHere, .alreadyMoved, .nobody, .sameSite:
            return String(localized: "Tick who went.")
        }
    }

    /// A time as the picker's date. Moving the time they left takes the time
    /// they started with it while the two were the same, as they usually are.
    private func timeBinding(_ time: Binding<TimeOfDay>, keepsStartedAfter: Bool) -> Binding<Date> {
        Binding(
            get: { OptionalTimeRow.date(from: time.wrappedValue, in: calendar) },
            set: { date in
                let new = OptionalTimeRow.time(from: date, in: calendar)
                if keepsStartedAfter && (started == time.wrappedValue || started < new) { started = new }
                time.wrappedValue = new
            }
        )
    }
}
