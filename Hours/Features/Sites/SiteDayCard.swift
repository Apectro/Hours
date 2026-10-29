import SwiftUI

/// One site day on one rounded surface (mockup board 4): the day and the
/// crew's total, the site's times once for everyone, then each person with a
/// tick, a way to the crew list, and the note at the bottom.
///
/// Draws and reports, nothing more. Every change goes back to the site screen
/// through a callback, because that is where the month lock, the refusal and
/// your calendar day are handled — a card that wrote on its own would be a
/// second way in that could forget one of them.
struct SiteDayCard: View {
    let title: String
    let day: SiteDay
    let result: SiteDayResult
    let rows: [PersonReference]
    /// Whether anything is stored for the day. An unstored day says so where
    /// a written one shows its total.
    let isWritten: Bool
    let canEdit: Bool
    let warnings: [DayWarning]
    let formatting: CalendarFormatting
    let durations: DurationFormatting
    @Binding var noteText: String
    var isNoteFocused: FocusState<Bool>.Binding
    /// "Saved" beside the title, for a moment after each write.
    var showsSaved = false
    /// The day types, for why someone was not here
    /// (`DayTypeCatalog.absenceReasons`) and how a reason is shown.
    let dayTypes: DayTypeCatalog
    /// Your other active sites, for "On another site".
    let otherSites: [Site]
    /// Every site's name by id, archived ones too, for a reason naming one.
    let siteNames: [UUID: String]
    /// Who was ticked on another of your sites that day, and which: shown
    /// greyed as a hint until confirmed, never stored on its own.
    let elsewhere: [UUID: UUID]
    let onToggle: (UUID) -> Void
    /// A reason someone not ticked was away, or nil for none.
    let onSetReason: (UUID, AbsenceReason?) -> Void
    let onEditPerson: (PersonReference) -> Void
    let onEditTimes: () -> Void
    /// Opens the site's crew list, to add someone or change a name.
    let onEditCrew: () -> Void
    /// Field allowance and kilometres (1.2), only while they are tracked:
    /// the allowance per person in the row's menu, and the vehicle's
    /// kilometres for the day in a row under the crew.
    var tracksAllowance = false
    var onToggleAllowance: (UUID) -> Void = { _ in }
    var kilometres: Binding<String> = .constant("")
    var isKilometresFocused: FocusState<Bool>.Binding? = nil
    /// "Moved to another site…" (1.2): offered while someone ticked has not
    /// moved yet and there is another active site. Nil is everyone ticked;
    /// a row's menu passes one person.
    var canMove = false
    var onMove: (UUID?) -> Void = { _ in }
    var onUndoMove: (SiteMove) -> Void = { _ in }

    // Not private: a private property would make the memberwise initializer
    // the site screen calls private too.
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            header
            timesRow
            warningsView
            ForEach(day.moves) { move in
                moveBanner(move)
            }

            // The app's one section-heading style (`SectionHeading`), as
            // "Extra work" below uses.
            SectionHeading(verbatim: String(
                localized: "Crew · \(result.people.count) of \(rows.count) here",
                comment: "Above the crew on a site day; the values are how many were there and how many could have been"
            ))
            .padding(.top, Metrics.tiny)

            VStack(spacing: Metrics.tiny) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    SitePersonRow(
                        row: row,
                        index: index,
                        person: result.people.first(where: { $0.memberID == row.id }),
                        exception: SiteException.of(row.id, in: day),
                        reason: day.absenceReason(for: row.id),
                        hint: day.attendance(for: row.id) == nil && day.absenceReason(for: row.id) == nil
                            ? elsewhere[row.id]
                            : nil,
                        dayTypes: dayTypes,
                        otherSites: otherSites,
                        siteNames: siteNames,
                        date: day.date,
                        canEdit: canEdit,
                        formatting: formatting,
                        durations: durations,
                        onToggle: { onToggle(row.id) },
                        onSetReason: { onSetReason(row.id, $0) },
                        onEdit: { onEditPerson(row) },
                        hasAllowance: day.hasAllowance(for: row.id),
                        tracksAllowance: tracksAllowance,
                        onToggleAllowance: { onToggleAllowance(row.id) },
                        movedTo: movedSiteName(of: row.id),
                        canMove: canMove && day.move(of: row.id) == nil,
                        onMove: { onMove(row.id) }
                    )
                }
            }

            if canMove {
                Button {
                    onMove(nil)
                } label: {
                    Label("Moved to another site…", systemImage: "arrow.left.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, Metrics.small)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("site-day-move")
            }

            // Open even when the day cannot be changed: the crew list says
            // for itself what can be done there.
            Button(action: onEditCrew) {
                Label("Add or edit crew", systemImage: "person.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, Metrics.small)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("site-day-edit-crew")

            if tracksAllowance {
                kilometresRow
            }

            Divider()

            // The one line for this day that goes on the Site sheet. The
            // diary below is the longer record, printed on pages of its own.
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                Text("Note on the sheet")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    text: $noteText,
                    prompt: Text("Short note printed in this day's row"),
                    axis: .vertical
                ) {
                    Text("Note on the sheet")
                }
                .lineLimit(1...5)
                .focused(isNoteFocused)
                .disabled(!canEdit)
                .frame(minHeight: 44)
                .accessibilityIdentifier("site-day-note")
            }
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    // MARK: - Moves

    /// The other site's name for someone who left this day for it, while
    /// they are still ticked here with the end the move gave them.
    private func movedSiteName(of memberID: UUID) -> String? {
        guard let move = day.move(of: memberID),
              let mine = day.resolved(for: memberID), mine.end == move.left
        else { return nil }
        return siteNames[move.toSiteID] ?? String(localized: "Another site")
    }

    /// "4 went to Trg Pravde at 11:30", with Undo (mockup After).
    private func moveBanner(_ move: SiteMove) -> some View {
        HStack(spacing: Metrics.small) {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(moveText(move))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("site-move-banner")
            if canEdit {
                Button("Undo") { onUndoMove(move) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("site-move-undo")
            }
        }
        .padding(.horizontal, Metrics.medium)
        .padding(.vertical, Metrics.tiny)
        .background(
            Color.accentColor.opacity(0.10),
            in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    /// One sentence, the who and where in bold: "**4 went to Trg Pravde** at
    /// 11:30".
    private func moveText(_ move: SiteMove) -> AttributedString {
        let site = siteNames[move.toSiteID] ?? String(localized: "Another site")
        let time = formatting.time(move.left, on: day.date)
        let ids = move.memberIDs
        if ids == [CrewMember.youID] {
            return AttributedString(localized: "**You went to \(site)** at \(time)", comment: "Site day banner, you alone moved; the values are the other site and a time")
        }
        if ids.count == 1, let name = rows.first(where: { $0.id == ids[0] })?.name {
            return AttributedString(localized: "**\(name) went to \(site)** at \(time)", comment: "Site day banner; the values are a person, the other site and a time")
        }
        return AttributedString(localized: "**\(ids.count) went to \(site)** at \(time)", comment: "Site day banner; the values are how many moved, the other site and a time")
    }

    // MARK: - Kilometres

    /// One number for the day: what the crew's vehicle drove. It goes on the
    /// sheet's closing lines, and to your own day when you were there.
    @ViewBuilder
    private var kilometresRow: some View {
        let field = TextField("Kilometres", text: kilometres)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .font(.hoursFigure(.body, weight: .medium))
            .frame(minWidth: 64, minHeight: 44)
            .disabled(!canEdit)
            .accessibilityIdentifier("site-day-kilometres")
        HStack(spacing: Metrics.small) {
            Label("Kilometres", systemImage: "car")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: Metrics.small)
            if let isKilometresFocused {
                field.focused(isKilometresFocused)
            } else {
                field
            }
            Text(verbatim: "km")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Metrics.small)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if showsSaved {
                Label("Saved", systemImage: "checkmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                    .accessibilityIdentifier("site-day-saved")
            }
            Spacer(minLength: Metrics.small)
            if isWritten {
                Text(durations.string(result.crewTotalMinutes))
                    .font(.hoursFigure(.headline))
                    .contentTransition(.numericText())
                    .accessibilityLabel(String(
                        localized: "Crew total: \(durations.string(result.crewTotalMinutes))",
                        comment: "VoiceOver, the crew's hours on a site day; the value is a duration"
                    ))
                    .accessibilityIdentifier("site-crew-total")
            } else {
                Text("Not written")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.hoursNegative)
                    .accessibilityIdentifier("site-day-not-written")
            }
        }
    }

    // MARK: - Site times

    private var timesRow: some View {
        // At the largest text sizes the times need the whole width, so
        // "Change" goes underneath instead of squeezing them to "7:00 AM –…".
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.small))
            : AnyLayout(HStackLayout(spacing: Metrics.medium))
        return Button(action: onEditTimes) {
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timesText)
                        .font(.hoursFigure(.title2))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(0.7)
                    Text(breakText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: Metrics.small)
                }
                Text("Change")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(canEdit ? Color.accentColor : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.medium)
            .frame(minHeight: 44)
            .background(
                Color.hoursCanvas,
                in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("site-day-times")
    }

    private var timesText: String {
        let start = day.start.map { formatting.time($0, on: day.date) } ?? "—"
        let end = day.end.map { formatting.time($0, on: day.date) } ?? "—"
        return "\(start) – \(end)"
    }

    private var breakText: String {
        guard day.breakMinutes > 0 else {
            return String(localized: "No break · everyone")
        }
        // Hours and minutes whatever the display setting, as on the sheet's
        // chips: "0:30 break" reads like a time of day.
        let length = DurationFormatting(style: .hoursAndMinutes).string(day.breakMinutes)
        return String(
            localized: "\(length) break · everyone",
            comment: "Under a site day's times; the value is a duration such as 30m"
        )
    }

    /// Quiet, as in the day editor: a half-entered day is a normal state while
    /// typing. Each warning once, however many people it applies to — with no
    /// end time it applies to all of them, and saying so per person is noise.
    @ViewBuilder
    private var warningsView: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ForEach(warnings) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(warning.isProblem ? Color.hoursNegative : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One person on a site day: who, their times, their hours and the tick.
///
/// The whole row is the tick, at least 56 points tall, so a gloved tap
/// anywhere on it does the one thing a row does. Changing just this person's
/// times is a separate 44-point clock button at the end, shown only while
/// they are ticked — it used to be the line of times under the name, a
/// 26-point target stacked on the name's, and a tap meant for it ticked the
/// person out instead. The same is offered on a long press.
struct SitePersonRow: View {
    let row: PersonReference
    /// The row's place on the card, for the reason button's identifier.
    let index: Int
    let person: PersonDay?
    let exception: SiteException?
    /// Why they were not here, when a reason was given.
    let reason: AbsenceReason?
    /// The other site they were ticked on that day, while no reason is given.
    let hint: UUID?
    let dayTypes: DayTypeCatalog
    let otherSites: [Site]
    let siteNames: [UUID: String]
    let date: CalendarDate
    let canEdit: Bool
    let formatting: CalendarFormatting
    let durations: DurationFormatting
    let onToggle: () -> Void
    let onSetReason: (AbsenceReason?) -> Void
    let onEdit: () -> Void
    /// Gets the field allowance today; a small mark beside the name, and a
    /// switch in the long-press menu while the allowance is tracked.
    var hasAllowance = false
    var tracksAllowance = false
    var onToggleAllowance: () -> Void = {}
    /// The site they left for (1.2): their times read "7:00 – 11:30 → Trg
    /// Pravde" in the accent colour rather than as leaving early.
    var movedTo: String? = nil
    /// Whether the menu offers "Moved to another site…" for them alone.
    var canMove = false
    var onMove: () -> Void = {}

    // Not `private`: that would make the memberwise initializer private too.
    @ScaledMetric(relativeTo: .subheadline) var initialsDiameter: CGFloat = 36

    private var isHere: Bool { person != nil }

    /// The day type, when that is the reason.
    private var absence: DayTypeDefinition? {
        guard case let .dayType(id)? = reason else { return nil }
        return dayTypes.definition(for: id)
    }

    /// "At Bau Süd", or "Another site" when no site was named or it is gone.
    private func atSite(_ siteID: UUID?) -> String {
        guard let name = siteID.flatMap({ siteNames[$0] }) else {
            return String(localized: "Another site")
        }
        return String(localized: "At \(name)", comment: "A crew row: working on another site that day; the value is its name")
    }

    /// The same, inside VoiceOver's "Ivan, at Bau Süd".
    private func atSiteInRunningText(_ siteID: UUID?) -> String {
        guard let name = siteID.flatMap({ siteNames[$0] }) else {
            return String(localized: "on another site")
        }
        return String(localized: "at \(name)", comment: "VoiceOver after a name: working on another site; the value is its name")
    }
    private var isYou: Bool { row.id == CrewMember.youID }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: Metrics.medium) {
                    initials

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Metrics.tiny) {
                            Text(row.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .opacity(isHere ? 1 : 0.55)
                            if showsAllowance {
                                Image(systemName: "suitcase.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        if let absence {
                            AbsenceChip(title: absence.displayName(), color: absence.tint.color)
                        } else if case let .otherSite(siteID)? = reason {
                            AbsenceChip(title: atSite(siteID), color: .gray)
                        } else if let hint {
                            // Only a hint: greyed until the reason button
                            // confirms it.
                            AbsenceChip(title: atSite(hint), color: .gray)
                                .opacity(0.55)
                        } else if let movedTo, let person {
                            Text(verbatim: "\(timeRange(person)) → \(movedTo)")
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(exception != nil ? Color.hoursNegative : Color.secondary)
                                .opacity(isHere ? 1 : 0.55)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(person.map { durations.string($0.workedMinutes) } ?? "—")
                        .font(.hoursFigure(.subheadline, weight: .medium))
                        .foregroundStyle(isHere ? Color.primary : Color.secondary)
                        .opacity(isHere ? 1 : 0.55)
                    Image(systemName: isHere ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isHere ? Color.accentColor : Color.secondary)
                }
                .padding(.vertical, Metrics.tiny)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            // One element read as the name, with whether they are here and
            // their hours as its value; the selected trait is the tick.
            .accessibilityLabel(row.name)
            .accessibilityValue(toggleValue)
            .accessibilityAddTraits(isHere ? .isSelected : [])
            .accessibilityIdentifier(isYou ? "site-person-you" : "site-person-\(row.name)")
            // The menu's allowance switch, for VoiceOver without a long press.
            .accessibilityActions {
                if canEdit && canMove && isHere {
                    Button("Moved to another site…", action: onMove)
                }
                if canEdit && tracksAllowance && isHere {
                    if hasAllowance {
                        Button("Take off the field allowance", action: onToggleAllowance)
                    } else {
                        Button("Give the field allowance", action: onToggleAllowance)
                    }
                }
            }

            if !isHere {
                reasonButton
            } else {
                Button(action: onEdit) {
                    Image(systemName: "clock")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(canEdit ? Color.accentColor : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)
                .padding(.leading, Metrics.tiny)
                // Says whose times and what they are, so VoiceOver need not
                // go back to the row to know what it would change.
                .accessibilityLabel(Text("Change times") + Text(verbatim: ", \(row.name), \(subtitle)"))
                .accessibilityIdentifier(isYou ? "site-times-you" : "site-times-\(row.name)")
            }
        }
        .padding(.horizontal, Metrics.small)
        .background(
            exception != nil && movedTo == nil ? Color.hoursNegativeFill.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
        )
        .contextMenu {
            if canEdit {
                Button(action: onToggle) {
                    if isHere {
                        Label("Not here", systemImage: "circle")
                    } else {
                        Label("Here", systemImage: "checkmark.circle")
                    }
                }
                if isHere {
                    Button(action: onEdit) {
                        Label("Change times", systemImage: "clock")
                    }
                    if canMove {
                        Button(action: onMove) {
                            Label("Moved to another site…", systemImage: "arrow.left.arrow.right")
                        }
                        .accessibilityIdentifier("site-person-move")
                    }
                    if tracksAllowance {
                        Button(action: onToggleAllowance) {
                            if hasAllowance {
                                Label("Field allowance", systemImage: "checkmark")
                            } else {
                                Label("Field allowance", systemImage: "suitcase")
                            }
                        }
                        .accessibilityIdentifier("site-person-allowance")
                    }
                } else {
                    Menu {
                        reasonItems
                    } label: {
                        Label("Why not here", systemImage: "questionmark.circle")
                    }
                }
            }
        }
    }

    // MARK: - Why not here

    /// In place of the clock while someone is not ticked: 44 points, opening
    /// the reasons. Shows the reason's own symbol once one is given. While
    /// another site is only a hint, a tap confirms it and a long press opens
    /// the reasons.
    @ViewBuilder
    private var reasonButton: some View {
        if let hint {
            Menu {
                reasonItems
            } label: {
                reasonLabel
            } primaryAction: {
                onSetReason(.otherSite(hint))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .padding(.leading, Metrics.tiny)
            .accessibilityLabel(Text("Why not here") + Text(verbatim: ", \(row.name)"))
            .accessibilityValue(atSite(hint))
            .accessibilityHint(Text("Tap to confirm. Touch and hold for other reasons."))
            .accessibilityIdentifier("site-absence-\(index)")
        } else {
            Menu {
                reasonItems
            } label: {
                reasonLabel
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .padding(.leading, Metrics.tiny)
            .accessibilityLabel(Text("Why not here") + Text(verbatim: ", \(row.name)"))
            .accessibilityValue(reasonValue)
            .accessibilityIdentifier("site-absence-\(index)")
        }
    }

    private var reasonLabel: some View {
        Image(systemName: reasonSymbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(canEdit ? (absence?.tint.color ?? Color.accentColor) : Color.secondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private var reasonSymbol: String {
        switch reason {
        case let .dayType(id)?: return dayTypes.definition(for: id).symbolName
        case .otherSite?: return "building.2"
        case nil: return hint == nil ? "questionmark.circle" : "building.2"
        }
    }

    private var reasonValue: String {
        switch reason {
        case .dayType?: return absence?.displayName() ?? ""
        case let .otherSite(siteID)?: return atSite(siteID)
        case nil: return String(localized: "No reason")
        }
    }

    /// On another site first, then every day type, then "No reason". The
    /// one given has a checkmark.
    @ViewBuilder
    private var reasonItems: some View {
        Menu {
            ForEach(Array(otherSites.enumerated()), id: \.element.id) { offset, site in
                Button {
                    onSetReason(.otherSite(site.id))
                } label: {
                    if reason == .otherSite(site.id) {
                        Label(site.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: site.name)
                    }
                }
                .accessibilityIdentifier("site-absence-other-site-\(offset)")
            }
            Button {
                onSetReason(.otherSite(nil))
            } label: {
                if reason == .otherSite(nil) {
                    Label("Another site", systemImage: "checkmark")
                } else {
                    Text("Another site")
                }
            }
            .accessibilityIdentifier("site-absence-other-site-any")
        } label: {
            Label("On another site", systemImage: "building.2")
        }
        .accessibilityIdentifier("site-absence-reason-other-site")

        ForEach(dayTypes.absenceReasons) { option in
            Button {
                onSetReason(.dayType(option.id))
            } label: {
                if reason == .dayType(option.id) {
                    Label(option.displayName(), systemImage: "checkmark")
                } else {
                    Label(option.displayName(), systemImage: option.symbolName)
                }
            }
            .accessibilityIdentifier("site-absence-reason-\(option.id.rawValue)")
        }
        Divider()
        Button {
            onSetReason(nil)
        } label: {
            if reason == nil {
                Label("No reason", systemImage: "checkmark")
            } else {
                Text("No reason")
            }
        }
        .accessibilityIdentifier("site-absence-reason-none")
    }

    // MARK: - Pieces

    private var initials: some View {
        ZStack {
            Circle()
                .fill(isHere ? Color.accentColor.opacity(0.15) : Color.hoursSubdued.opacity(0.2))
            if isYou {
                Image(systemName: "person.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isHere ? Color.accentColor : Color.secondary)
            } else {
                Text(verbatim: Self.initials(of: row.name))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(isHere ? Color.accentColor : Color.secondary)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: initialsDiameter, height: initialsDiameter)
        .opacity(isHere ? 1 : 0.55)
    }

    /// Up to two letters, from the first two words of the name.
    static func initials(of name: String) -> String {
        name.split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { word in word.first.map { String($0) } }
            .joined()
            .uppercased()
    }

    private var subtitle: String {
        guard let person else { return String(localized: "Not here") }
        let times = timeRange(person)
        guard let exception else { return times }
        return "\(exceptionTitle(exception)) · \(times)"
    }

    private var toggleValue: String {
        // "Ivan, sick leave", "Ivan, at Bau Süd": why they were away is
        // what there is to say.
        if let absence { return absence.nameInRunningText() }
        if case let .otherSite(siteID)? = reason { return atSiteInRunningText(siteID) }
        if let hint { return atSiteInRunningText(hint) }
        guard let person else { return String(localized: "Not here") }
        var parts = [String(localized: "Here"), durations.string(person.workedMinutes)]
        if let movedTo {
            parts.append(String(localized: "then at \(movedTo)", comment: "VoiceOver after a crew member's hours: they moved on to another site; the value is its name"))
        }
        if showsAllowance { parts.append(String(localized: "field allowance")) }
        return parts.joined(separator: ", ")
    }

    private var showsAllowance: Bool { tracksAllowance && isHere && hasAllowance }

    private func exceptionTitle(_ exception: SiteException) -> String {
        switch exception {
        case .cameLate: return String(localized: "Came late")
        case .leftEarly: return String(localized: "Left early")
        case .changedTimes: return String(localized: "Own times")
        }
    }

    private func timeRange(_ person: PersonDay) -> String {
        let start = person.start.map { formatting.time($0, on: date) } ?? "—"
        let end = person.end.map { formatting.time($0, on: date) } ?? "—"
        return "\(start) – \(end)"
    }
}

/// Why someone was not on site, small: a day type's colour and name, or the
/// other site they were on.
struct AbsenceChip: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: Metrics.tiny) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, Metrics.small)
        .padding(.vertical, Metrics.tiny)
        .background(
            color.opacity(0.16),
            in: RoundedRectangle(cornerRadius: Metrics.chipCornerRadius, style: .continuous)
        )
        .fixedSize()
    }
}

/// A row of the crew list: who, and the name to show.
struct PersonReference: Identifiable, Hashable {
    let id: UUID
    let name: String
}
