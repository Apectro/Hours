import SwiftUI
import SwiftData

// MARK: - Why nobody worked, in words

extension SiteNoWorkReason {
    /// The reason as the sheet and the day say it.
    var title: String {
        switch self {
        case .crewElsewhere: return String(localized: "Crew on another site")
        case .noWork: return String(localized: "No work")
        case .badWeather: return String(localized: "Bad weather")
        case .dayOff: return String(localized: "Holiday / day off")
        }
    }

    /// One line under the reason in the menu, where the word alone is not
    /// enough.
    var detail: String? {
        switch self {
        case .noWork: return String(localized: "Waiting for other trades, no material")
        default: return nil
        }
    }

    var systemImage: String {
        switch self {
        case .crewElsewhere: return "arrow.right"
        case .noWork: return "pause.circle"
        case .badWeather: return "cloud.rain"
        case .dayOff: return "sun.max"
        }
    }

    /// "No work · Bad weather", or "No work" for the plain reason.
    var summary: String {
        guard self != .noWork else { return String(localized: "No work") }
        return String(localized: "No work · \(title)", comment: "A site day nobody worked; the value is why, e.g. Bad weather")
    }
}

/// A day recorded as "no work", on the site's day: what it is and Undo, as
/// the bad-weather row does.
struct SiteNoWorkRow: View {
    let reason: SiteNoWorkReason
    let canEdit: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Metrics.medium) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: reason.summary)
                        .font(.subheadline.weight(.semibold))
                    Text("Nobody gets hours for this day.")
                        .font(.footnote)
                        .foregroundStyle(.hoursSecondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: reason.systemImage)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("site-day-no-work")
            Spacer(minLength: Metrics.small)
            if canEdit {
                Button("Undo", action: onUndo)
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(String(localized: "Undo no work"))
                    .accessibilityIdentifier("site-day-no-work-undo")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What the sheet is opened for: a site and the month whose "N not
/// written" was tapped.
struct SiteNoWorkRequest: Identifiable, Hashable {
    let site: Site
    let month: YearMonth

    var id: String { "\(site.id.uuidString)-\(month.year)-\(month.month)" }
}

/// "N not written", tapped (the Sites list and the site's page): the days,
/// each with the reasons nobody worked, and "All N" at the top. A reason
/// records the site day as "no work" (`SiteDay.noWork`): no hours for
/// anyone and nobody's own day changed, except Bad weather, which is the
/// bad-weather stop with no work and types your own day as the stop does.
/// A day chosen here stays in the list with Undo until the sheet closes.
///
/// Every write goes through `SiteRepository` with the month lock; a day in
/// a closed month is listed without a choice. A read-only site never opens
/// this.
struct SiteNoWorkSheet: View {
    let request: SiteNoWorkRequest

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    /// The days listed, fixed when the sheet opens so a chosen day keeps its
    /// row for Undo.
    @State private var listed: [SiteNoWorkList.Day] = []
    /// What each listed day is now: still missing, no work for a reason,
    /// or written some other way since.
    @State private var stored: [CalendarDate: SiteNoWorkReason] = [:]
    @State private var stillMissing: Set<CalendarDate> = []
    @State private var loaded = false
    /// Set when a write is refused.
    @State private var refusal: Error?

    var body: some View {
        NavigationStack {
            List {
                if !open.isEmpty {
                    Section {
                        allRow
                    }
                }
                Section {
                    ForEach(listed, id: \.date) { day in
                        row(day)
                    }
                } footer: {
                    Text("Nobody worked here on these days? Choose why. Nobody gets hours, and nobody's own day changes, except with Bad weather.")
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("site-no-work-sheet")
            .navigationTitle(Text("Not written"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel(String(localized: "Done"))
                    .accessibilityIdentifier("site-no-work-done")
                }
            }
            .alert(
                "This month is closed",
                isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })
            ) {
                Button("OK", role: .cancel) { refusal = nil }
            } message: {
                Text("Reopen it to change these hours. You can close it again from the calendar's ⋯ menu.")
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard !loaded else { return }
            loaded = true
            load(initial: true)
        }
    }

    // MARK: - Rows

    /// The days still to choose for, in a month that is open.
    private var open: [SiteNoWorkList.Day] {
        listed.filter { stillMissing.contains($0.date) && !isLocked($0.date) }
    }

    /// "All 3": one reason for every day still open.
    private var allRow: some View {
        let days = open
        return Menu {
            reasonButtons(someoneElsewhere: days.contains(where: \.someoneElsewhere), identifier: "site-no-work-all") { reason in
                choose(reason, for: days.map(\.date))
            }
        } label: {
            HStack(spacing: Metrics.small) {
                Text(String(localized: "All \(days.count)", comment: "The not-written sheet: one reason for every day listed; the value is how many"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Spacer(minLength: Metrics.small)
                Text("Choose")
                    .foregroundStyle(.hoursSecondaryText)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("site-no-work-all")
    }

    @ViewBuilder
    private func row(_ day: SiteNoWorkList.Day) -> some View {
        let title = formatting.dayTitle(day.date)
        if let reason = stored[day.date] {
            HStack(spacing: Metrics.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                    Text(verbatim: reason.summary)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: Metrics.small)
                if !isLocked(day.date) {
                    Button("Undo") { undo(day.date) }
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(String(localized: "Undo no work"))
                        .accessibilityIdentifier("site-no-work-undo-\(day.date.key)")
                }
            }
        } else if !stillMissing.contains(day.date) {
            // Written some other way since: nothing to choose.
            LabeledContent {
                Text("Written")
            } label: {
                Text(verbatim: title)
            }
        } else if isLocked(day.date) {
            LabeledContent {
                Label("Month closed", systemImage: "lock.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.hoursSecondaryText)
            } label: {
                Text(verbatim: title)
            }
        } else {
            Menu {
                reasonButtons(someoneElsewhere: day.someoneElsewhere, identifier: "site-no-work-\(day.date.key)") { reason in
                    choose(reason, for: [day.date])
                }
            } label: {
                HStack(spacing: Metrics.small) {
                    Text(verbatim: title)
                        .foregroundStyle(.primary)
                    Spacer(minLength: Metrics.small)
                    Text("Choose")
                        .foregroundStyle(Color.accentColor)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("site-no-work-day-\(day.date.key)")
        }
    }

    /// The four reasons, "Crew on another site" first when it is true of
    /// some of the crew.
    @ViewBuilder
    private func reasonButtons(
        someoneElsewhere: Bool,
        identifier: String,
        action: @escaping (SiteNoWorkReason) -> Void
    ) -> some View {
        ForEach(SiteNoWorkReason.offered(someoneElsewhere: someoneElsewhere), id: \.self) { reason in
            Button {
                action(reason)
            } label: {
                if let detail = reason.detail {
                    Label {
                        Text(verbatim: reason.title)
                        Text(verbatim: detail)
                    } icon: {
                        Image(systemName: reason.systemImage)
                    }
                } else {
                    Label(reason.title, systemImage: reason.systemImage)
                }
            }
            .accessibilityIdentifier("\(identifier)-\(reason.rawValue)")
        }
    }

    // MARK: - Data

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
    private var siteID: UUID { request.site.id }

    private var repository: SiteRepository {
        SiteRepository(context: modelContext, lock: settings.monthLock)
    }

    private func isLocked(_ date: CalendarDate) -> Bool {
        settings.monthLock.isLocked(date)
    }

    /// The days the site was there to be worked, as its page reads them.
    private func active(store: SiteRepository, today: CalendarDate) -> SiteActiveDays {
        SiteMonthStatuses.activeDays(of: store.site(id: siteID) ?? request.site, repository: store, today: today, calendar: calendar)
    }

    /// The month's statuses as the site's page reads them; the listed days
    /// only the first time.
    private func load(initial: Bool) {
        let store = repository
        let month = request.month
        let range = month.range(in: calendar)
        let lookBack = CalendarDateRange(
            start: range.start.adding(days: -SiteWorkDays.lookBackDays, in: calendar),
            end: range.end
        )
        let allDays = store.siteDays(siteID: nil, in: lookBack)
        let members = store.sites(includeArchived: true).flatMap { store.crew(for: $0.id, includeHidden: true) }
        let today = CalendarDate.today(in: calendar)
        let statuses = SiteMonthStatuses.statuses(
            siteID: siteID,
            month: month,
            siteDays: allDays,
            members: members,
            settings: settings,
            calendar: calendar,
            today: today,
            holidays: SiteMonthStatuses.holidays(context: modelContext, settings: settings, calendar: calendar, range: lookBack),
            active: active(store: store, today: today)
        )
        if initial {
            let check = SiteMonthOverview.crew(
                siteID: siteID, members: members, siteDays: allDays, month: month, calendar: calendar
            )
            listed = SiteNoWorkList.days(statuses: statuses, month: month, check: check)
        }
        stillMissing = Set(statuses.filter { $0.value == .missing }.map(\.key))
        var reasons: [CalendarDate: SiteNoWorkReason] = [:]
        for day in allDays where day.siteID == siteID && range.contains(day.date) && day.isNoWorkDay {
            reasons[day.date] = day.noWork
        }
        stored = reasons
    }

    /// The days recorded as "no work" for `reason`, one save each, through
    /// the lock. Bad weather is the full stop of the usual crew's day.
    private func choose(_ reason: SiteNoWorkReason, for dates: [CalendarDate]) {
        let store = repository
        let site = store.site(id: siteID) ?? request.site
        let crew = [CrewMember.youID] + store.crew(for: siteID, includeHidden: false).map(\.id)
        for date in dates where store.siteDay(siteID: siteID, on: date) == nil {
            let usual = SiteDay(
                siteID: siteID, date: date,
                present: crew.map { Attendance(memberID: $0) },
                jobID: site.jobID
            )
            let day = SiteDay.noWork(reason, siteID: siteID, date: date, jobID: site.jobID, usual: usual)
            do {
                try store.save(day)
            } catch {
                refusal = error
                break
            }
        }
        afterWriting()
    }

    /// The day back as it was: nothing, unless something was written on it
    /// since.
    private func undo(_ date: CalendarDate) {
        let store = repository
        guard let day = store.siteDay(siteID: siteID, on: date), day.isNoWorkDay else {
            load(initial: false)
            return
        }
        let cleared = day.clearingNoWork()
        do {
            if cleared.isBlank {
                try store.delete(siteID: siteID, on: date)
            } else {
                try store.save(cleared)
            }
        } catch {
            refusal = error
        }
        afterWriting()
    }

    private func afterWriting() {
        load(initial: false)
        HoursStack.refreshWidget()
        let context = modelContext
        let settingsStore = settingsStore
        Task { await MonthlySheetRefresher.refresh(context: context, settingsStore: settingsStore) }
        Task {
            await SiteReminderRefresher.refresh(
                context: context,
                preferences: settingsStore.settings.reminders,
                calendar: settingsStore.workCalendar
            )
        }
    }
}
