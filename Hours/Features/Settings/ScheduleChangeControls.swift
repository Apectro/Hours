import SwiftUI

/// Asks when a changed week starts, before it is saved.
///
/// Saving a week used to rewrite every month since the app was installed:
/// a contract that changed in November recalculated October, closed months
/// and the running balance included. Now each change has a start, and this
/// is where the person says what it is — from today, from a date, or "it was
/// always like this", which is the old behaviour and is still sometimes what
/// is meant (a week entered wrongly from the start).
///
/// Used by Working schedule and by a job's editor, so the two ask the same
/// question in the same words — and by Pay, since a raise is the same kind of
/// change and has the same months to leave alone.
struct ScheduleChangePrompt<Value: DatedValue>: ViewModifier {
    @Binding var isPresented: Bool
    let history: DatedHistory<Value>
    var subject: DatedChangeSubject = .week
    let lock: MonthLock
    let calendar: Calendar
    let formatting: CalendarFormatting
    /// The day the new week starts, or nil for "it was always like this".
    let onChoose: (CalendarDate?) -> Void

    @State private var isPickingDate = false
    @State private var picked = Date()

    private var today: CalendarDate { CalendarDate.today(in: calendar) }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "When does this change start?",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("From today") { onChoose(today) }
                Button("From a date…") {
                    picked = Date()
                    isPickingDate = true
                }
                Button("It was always like this") { onChoose(nil) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(message)
            }
            .sheet(isPresented: $isPickingDate) {
                NavigationStack {
                    Form {
                        Section {
                            DatePicker(
                                "Starts on",
                                selection: $picked,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                        } footer: {
                            Text(pickedFooter)
                        }
                    }
                    .navigationTitle("From a date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isPickingDate = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                isPickingDate = false
                                onChoose(CalendarDate(picked, calendar: calendar))
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
    }

    /// What each answer leaves alone, and which closed months it would not.
    private var message: String {
        var parts = [subject == .week
            ? String(localized: "Days before the change keep the week they had.")
            : String(localized: "Days before the change keep the pay they had.")]
        let fromToday = history.closedMonths(affectedByChangeFrom: today, lock: lock)
        if !fromToday.isEmpty {
            parts.append(String(
                localized: "“From today” changes closed months: \(names(fromToday)).",
                comment: "Changing the working week; the value is a list of month names"
            ))
        }
        let always = history.closedMonths(affectedByChangeFrom: nil, lock: lock)
        if !always.isEmpty {
            parts.append(String(
                localized: "“It was always like this” changes closed months: \(names(always)).",
                comment: "Changing the working week; the value is a list of month names"
            ))
        }
        return parts.joined(separator: " ")
    }

    private var pickedFooter: String {
        let closed = history.closedMonths(
            affectedByChangeFrom: CalendarDate(picked, calendar: calendar),
            lock: lock
        )
        guard !closed.isEmpty else {
            return subject == .week
                ? String(localized: "The new week applies from this day on. Days before it keep the week they had.")
                : String(localized: "The new pay applies from this day on. Days before it keep the pay they had.")
        }
        return String(
            localized: "This changes closed months: \(names(closed)).",
            comment: "Changing the working week from a date; the value is a list of month names"
        )
    }

    private func names(_ months: [YearMonth]) -> String {
        ListFormatter.localizedString(byJoining: months.map { formatting.monthTitle($0) })
    }
}

/// What a dated change is a change of, for the words the prompt uses.
enum DatedChangeSubject {
    case week
    case pay
}

extension View {
    /// Asks when a changed week, or a change of pay, starts; see
    /// `ScheduleChangePrompt`.
    func scheduleChangePrompt<Value: DatedValue>(
        isPresented: Binding<Bool>,
        history: DatedHistory<Value>,
        subject: DatedChangeSubject = .week,
        lock: MonthLock,
        calendar: Calendar,
        formatting: CalendarFormatting,
        onChoose: @escaping (CalendarDate?) -> Void
    ) -> some View {
        modifier(ScheduleChangePrompt(
            isPresented: isPresented,
            history: history,
            subject: subject,
            lock: lock,
            calendar: calendar,
            formatting: formatting,
            onChoose: onChoose
        ))
    }
}

/// The changes a week has been through: "Changed on 3 Nov 2026 · earlier:
/// 40h a week", each of which can be taken back.
///
/// Nothing at all while the week has never changed, which is most people.
struct ScheduleHistorySection: View {
    let history: ScheduleHistory
    let today: CalendarDate
    let formatting: CalendarFormatting
    let durationFormatting: DurationFormatting
    /// Takes back the change that started on this day.
    let onRemove: (CalendarDate) -> Void

    var body: some View {
        if history.hasChanges {
            Section {
                ForEach(changes, id: \.from) { change in
                    Text(line(for: change))
                        .font(.subheadline)
                }
                .onDelete { offsets in
                    for index in offsets { onRemove(changes[index].from) }
                }
            } header: {
                Text("Changes")
            } footer: {
                Text("Swipe to remove a change. The week before it then runs on in its place.")
            }
        }
    }

    private struct Change {
        var from: CalendarDate
        var earlier: WorkSchedule
    }

    /// Newest first, each with the week it replaced.
    private var changes: [Change] {
        let versions = history.versions
        let oldestFirst = versions.indices.dropFirst().compactMap { index in
            versions[index].from.map { Change(from: $0, earlier: versions[index - 1].schedule) }
        }
        return Array(oldestFirst.reversed())
    }

    private func line(for change: Change) -> String {
        let date = formatting.dateWithYear(change.from)
        let weekly = durationFormatting.string(change.earlier.weeklyTargetMinutes)
        if change.from > today {
            return String(
                localized: "Changes on \(date) · until then: \(weekly) a week",
                comment: "A change of working week still to come; the values are a date and a duration"
            )
        }
        return String(
            localized: "Changed on \(date) · earlier: \(weekly) a week",
            comment: "A past change of working week; the values are a date and a duration"
        )
    }
}
