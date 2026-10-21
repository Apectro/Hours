import SwiftUI

/// What a job pays: the hourly rate, overtime, the surcharges, and paid days
/// off.
///
/// Reached from Settings for the main job and from each job's editor for the
/// others, so every job has its own. Free: what you are owed is a way of
/// reading hours you already recorded, and reading is never sold.
///
/// Edits collect in a draft, as the working week's do, because pay changes
/// from a date: a raise in March must not rewrite February. Save asks when
/// the change starts. The first rate a job is given needs no such question —
/// nothing earned anything before it — so it applies since always.
struct PaySettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    let jobID: UUID
    /// The choices that are not about one job — what the app leads with, and
    /// the currency — shown where the main job's pay is set.
    var showsGeneralSettings = true

    /// Nil until something is edited.
    @State private var draft: PayRules?
    @State private var isAskingWhen = false
    @State private var isConfirmingRemoval = false

    var body: some View {
        Form {
            rateSection
            overtimeSection
            surchargeSection
            nightSection
            absenceSection

            if let history = job.pay, history.hasChanges {
                PayHistorySection(
                    history: history,
                    today: today,
                    formatting: settingsStore.dateFormatting,
                    money: settings.money,
                    onRemove: { date in
                        settingsStore.update { $0.removePayChange(forJob: jobID, from: date) }
                        draft = nil
                    }
                )
            }

            if showsGeneralSettings {
                generalSection
            }

            if job.pay != nil {
                Section {
                    Button("Stop working out earnings", role: .destructive) { isConfirmingRemoval = true }
                } footer: {
                    Text("Removes this job's rate and every change to it. Your hours are not touched.")
                }
            }
        }
        .navigationTitle(settings.tracksMultipleJobs ? job.name : String(localized: "Pay"))
        .navigationBarTitleDisplayMode(.inline)
        // Leaving with unsaved pay would quietly drop it, so while there is
        // some the way out is Discard or Save.
        .navigationBarBackButtonHidden(hasChanges)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { draft = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: requestSave)
                        .fontWeight(.semibold)
                }
            }
        }
        .scheduleChangePrompt(
            isPresented: $isAskingWhen,
            history: job.pay ?? PayHistory(PayRules()),
            subject: .pay,
            lock: settings.monthLock,
            calendar: settingsStore.workCalendar,
            formatting: settingsStore.dateFormatting
        ) { start in
            save(from: start)
        }
        .confirmationDialog(
            "Stop working out earnings for this job?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Stop working out earnings", role: .destructive) {
                settingsStore.update { $0.removePay(forJob: jobID) }
                draft = nil
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var rateSection: some View {
        Section {
            HStack {
                Text("Hourly rate")
                Spacer(minLength: Metrics.small)
                TextField("Hourly rate", value: rateBinding, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.hoursFigure(.body, weight: .medium))
                    .accessibilityIdentifier("pay-hourly-rate")
                Text(verbatim: settings.money.currencyCode)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(rateFooter)
        }
    }

    private var overtimeSection: some View {
        Section {
            Picker("Overtime", selection: field(\.overtimeMode)) {
                Text("Same rate").tag(OvertimeMode.sameRate)
                Text("After my normal day").tag(OvertimeMode.afterDailyHours)
                Text("After my week").tag(OvertimeMode.afterWeeklyHours)
            }
            .pickerStyle(.inline)
            .labelsHidden()

            if edited.overtimeMode != .sameRate {
                PercentStepperRow(title: String(localized: "Overtime surcharge"), percent: field(\.overtimePercent))
                thresholdRows
            }
        } header: {
            Text("Overtime")
        } footer: {
            Text(overtimeFooter)
        }
    }

    @ViewBuilder
    private var thresholdRows: some View {
        let daily = edited.overtimeMode == .afterDailyHours
        let keyPath: WritableKeyPath<PayRules, Int?> = daily ? \.dailyThresholdMinutes : \.weeklyThresholdMinutes
        Toggle(
            daily ? String(localized: "Set my normal day by hand") : String(localized: "Set my week by hand"),
            isOn: Binding(
                get: { edited[keyPath: keyPath] != nil },
                set: { isOn in
                    var rules = edited
                    rules[keyPath: keyPath] = isOn ? (daily ? 8 * 60 : 40 * 60) : nil
                    draft = rules
                }
            )
        )
        if let minutes = edited[keyPath: keyPath] {
            DurationStepperRow(
                title: daily ? String(localized: "Normal day") : String(localized: "Normal week"),
                minutes: Binding(
                    get: { minutes },
                    set: { newValue in
                        var rules = edited
                        rules[keyPath: keyPath] = newValue
                        draft = rules
                    }
                ),
                range: daily ? 0...(24 * 60) : 0...(80 * 60),
                step: daily ? 15 : 30,
                formatting: settings.displayFormatting
            )
        }
    }

    /// Where the figures go, said where the rate is typed in, and with
    /// several jobs whose rate this is.
    private var rateFooter: String {
        let privacy = String(localized: "Only on this phone and in your backups. Never on site sheets.")
        guard settings.tracksMultipleJobs else { return privacy }
        let whose = String(
            localized: "This is what \(job.name) pays. Every job keeps its own rate.",
            comment: "Pay settings with several jobs; the value is a job's name"
        )
        return whose + " " + privacy
    }

    private var overtimeFooter: String {
        switch edited.overtimeMode {
        case .sameRate:
            return String(localized: "Every hour pays the same.")
        case .afterDailyHours:
            return String(localized: "Hours beyond your normal day pay the surcharge on top. Unless you set it here, your normal day is what your working schedule expects that day.")
        case .afterWeeklyHours:
            return String(localized: "Hours beyond your week pay the surcharge on top, counted from the first day of the week. Unless you set it here, your week is your working schedule's.")
        }
    }

    private var surchargeSection: some View {
        Section {
            PercentStepperRow(title: String(localized: "Saturday"), percent: field(\.saturdayPercent))
            PercentStepperRow(title: String(localized: "Sunday and public holidays"), percent: field(\.sundayAndHolidayPercent))
        } header: {
            Text("Surcharges")
        } footer: {
            Text("Added on top of the rate, and to each other: an hour on a Sunday night pays the Sunday and the night surcharge. Public holidays come from your holidays in Settings.")
        }
    }

    private var nightSection: some View {
        Section {
            PercentStepperRow(title: String(localized: "Night"), percent: field(\.nightPercent))
            if edited.nightPercent > 0 {
                OptionalTimeRow(
                    title: String(localized: "From"),
                    time: Binding(
                        get: { edited.nightStart },
                        set: { newValue in if let newValue { update { $0.nightStart = newValue } } }
                    ),
                    calendar: settingsStore.workCalendar,
                    fallback: TimeOfDay(hour: 22, minute: 0)
                )
                OptionalTimeRow(
                    title: String(localized: "Until"),
                    time: Binding(
                        get: { edited.nightEnd },
                        set: { newValue in if let newValue { update { $0.nightEnd = newValue } } }
                    ),
                    calendar: settingsStore.workCalendar,
                    fallback: TimeOfDay(hour: 6, minute: 0)
                )
            }
        } footer: {
            Text("The minutes of a shift that fall in the night window, across midnight too.")
        }
    }

    private var absenceSection: some View {
        Section {
            Toggle("Paid days off earn money", isOn: field(\.paidAbsenceEarns))
        } footer: {
            Text("Vacation, sick days and public holidays earn the hours credited for them, at the rate, with no surcharges.")
        }
    }

    private var generalSection: some View {
        Section {
            Picker("Main figure", selection: settingsStore.binding(\.mainFigure)) {
                Text("Earnings").tag(MainFigure.earnings)
                Text("Hours balance").tag(MainFigure.hoursBalance)
            }
            Picker("Currency", selection: currencyBinding) {
                ForEach(currencyCodes, id: \.self) { code in
                    Text(currencyName(code)).tag(code)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Showing earnings")
        } footer: {
            Text("With a rate set, the calendar, Insights and the widgets lead with what you earned. Choose Hours balance to see your hours ahead or behind instead. Nothing about money ever appears on a site, its sheet or anyone in your crew.")
        }
    }

    // MARK: - State

    private var settings: AppSettings { settingsStore.settings }
    private var job: Job { settings.job(jobID) }
    private var today: CalendarDate { CalendarDate.today(in: settingsStore.workCalendar) }

    /// The pay in force today, which is what the screen shows and edits.
    private var current: PayRules { job.pay?.value(on: today) ?? PayRules() }
    private var edited: PayRules { draft ?? current }

    /// A job with no rate yet has nothing to save until it has one.
    private var hasChanges: Bool {
        guard let draft, draft != current else { return false }
        return job.pay != nil || draft.hourlyRateCents > 0
    }

    private func update(_ change: (inout PayRules) -> Void) {
        var rules = edited
        change(&rules)
        draft = rules
    }

    private func field<Value>(_ keyPath: WritableKeyPath<PayRules, Value>) -> Binding<Value> {
        Binding(
            get: { edited[keyPath: keyPath] },
            set: { newValue in update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private var rateBinding: Binding<Decimal> {
        Binding(
            get: { PayRules.amount(fromCents: edited.hourlyRateCents) },
            set: { newValue in update { $0.hourlyRateCents = PayRules.cents(from: newValue) } }
        )
    }

    /// Nil follows the phone, so choosing the phone's own currency stores
    /// nothing and a phone moved to another region follows it.
    private var currencyBinding: Binding<String> {
        Binding(
            get: { settings.money.currencyCode },
            set: { code in
                settingsStore.update { $0.currencyCode = code == AppSettings.deviceCurrencyCode ? nil : code }
            }
        )
    }

    private var currencyCodes: [String] {
        var codes = Locale.commonISOCurrencyCodes
        let chosen = settings.money.currencyCode
        if !codes.contains(chosen) { codes.append(chosen) }
        return codes.sorted()
    }

    private func currencyName(_ code: String) -> String {
        guard let name = Locale.current.localizedString(forCurrencyCode: code) else { return code }
        return "\(name) (\(code))"
    }

    // MARK: - Saving

    private func requestSave() {
        guard job.pay != nil else {
            save(from: nil)
            return
        }
        isAskingWhen = true
    }

    private func save(from start: CalendarDate?) {
        guard let draft else { return }
        settingsStore.update { $0.changePay(forJob: jobID, to: draft, from: start) }
        self.draft = nil
        HoursStack.refreshWidget()
    }
}

/// A surcharge as a percentage on top of the rate, in steps of five.
struct PercentStepperRow: View {
    let title: String
    @Binding var percent: Int

    var body: some View {
        Stepper(value: $percent, in: 0...300, step: 5) {
            HStack {
                Text(title)
                Spacer(minLength: Metrics.small)
                Text(text)
                    .font(.hoursFigure(.body, weight: .medium))
                    .foregroundStyle(percent > 0 ? Color.primary : Color.secondary)
            }
        }
        .accessibilityValue(text)
    }

    private var text: String {
        percent > 0 ? "+" + (Double(percent) / 100).formatted(.percent) : String(localized: "None")
    }
}

/// The changes a job's pay has been through, newest first, each of which can
/// be taken back — the pay counterpart of `ScheduleHistorySection`.
struct PayHistorySection: View {
    let history: PayHistory
    let today: CalendarDate
    let formatting: CalendarFormatting
    let money: MoneyFormatting
    let onRemove: (CalendarDate) -> Void

    var body: some View {
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
            Text("Swipe to remove a change. The pay before it then runs on in its place.")
        }
    }

    private struct Change {
        var from: CalendarDate
        var earlier: PayRules
    }

    private var changes: [Change] {
        let versions = history.versions
        let oldestFirst = versions.indices.dropFirst().compactMap { index in
            versions[index].from.map { Change(from: $0, earlier: versions[index - 1].value) }
        }
        return Array(oldestFirst.reversed())
    }

    private func line(for change: Change) -> String {
        let date = formatting.dateWithYear(change.from)
        let rate = money.string(change.earlier.hourlyRateCents)
        if change.from > today {
            return String(
                localized: "Changes on \(date) · until then: \(rate) an hour",
                comment: "A change of pay still to come; the values are a date and an amount"
            )
        }
        return String(
            localized: "Changed on \(date) · earlier: \(rate) an hour",
            comment: "A past change of pay; the values are a date and an amount"
        )
    }
}
