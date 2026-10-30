import SwiftUI

/// Where the setup's last screen leads.
enum FirstRunFinish: String, Identifiable {
    case writeToday
    case createSite
    /// "Show me around": the guided tour, over the calendar.
    case tour

    var id: String { rawValue }
}

/// The questions a fresh install asks once (1.2 redesign, board 01): your
/// name, your usual day and whether your breaks are paid, where you work, the language of the sheets for your
/// boss, whether you lead a crew, and your pay. One question per screen,
/// every one of them skippable, and each answer saved as you continue past
/// it, so skipping later keeps what was already answered.
struct FirstRunSetupView: View {
    /// `nil` when skipped.
    let onFinish: (FirstRunFinish?) -> Void

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext

    @State private var step: Step = .name
    @State private var answers = FirstRunAnswers(settings: AppSettings())
    /// The settings as they were before the first answer, which is what a
    /// step falls back to when no country suggests anything.
    @State private var settingsBefore = AppSettings()
    @State private var hasLoaded = false
    @State private var holidayCountry: HolidayCountry?
    @State private var holidayRegion: String?
    /// Picked by hand: a later change of country no longer preselects them.
    @State private var languageWasChosen = false
    @State private var currencyWasChosen = false

    /// Whether breaks are paid is asked on the week's screen (1.2).
    enum Step: Int {
        case name, week, holidays, language, crew, pay, finish

        /// The steps with a question, counted in "2 of 6".
        static let questionCount = 6
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .name:
                    SetupNameStep(name: $answers.name, onReturn: advance)
                case .week:
                    SetupWeekStep(answers: $answers)
                case .holidays:
                    SetupHolidaysStep(country: $holidayCountry, region: $holidayRegion) {
                        holidayCountry = nil
                        holidayRegion = nil
                        advance()
                    }
                case .language:
                    SetupLanguageStep(language: $answers.reportLanguage) { languageWasChosen = true }
                case .crew:
                    SetupCrewStep(leadsCrew: $answers.leadsCrew)
                case .pay:
                    SetupPayStep(hourlyRateCents: $answers.hourlyRateCents, currencyCode: $answers.currencyCode) {
                        currencyWasChosen = true
                    }
                case .finish:
                    SetupFinishStep(name: answers.name, onFinish: onFinish)
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                if step != .finish {
                    bottomActions
                }
            }
        }
        .onAppear {
            // Once: the answers start from the settings, and coming back to
            // this view must not throw away what has been typed.
            guard !hasLoaded else { return }
            hasLoaded = true
            settingsBefore = settingsStore.settings
            answers = FirstRunAnswers(settings: settingsStore.settings)
        }
    }

    /// Back, "2 of 6" in the middle, and Skip: the system's toolbar, no
    /// bar of our own (design v2).
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if step != .name && step != .finish {
                Button(action: goBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("setup-back")
            }
        }
        ToolbarItem(placement: .principal) {
            if step != .finish {
                Text(String(
                    localized: "\(step.rawValue + 1) of \(Step.questionCount)",
                    comment: "First-run setup progress, such as 2 of 6"
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.hoursSecondaryText)
                .monospacedDigit()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if step != .finish {
                Button("Skip") { onFinish(nil) }
                    .accessibilityIdentifier("setup-skip")
            }
        }
    }

    /// Continue, the one main action, at the bottom; on the pay step
    /// "Skip pay" beside it.
    private var bottomActions: some View {
        HStack(spacing: Metrics.medium) {
            if step == .pay {
                Button {
                    answers.hourlyRateCents = 0
                    advance()
                } label: {
                    Text("Skip pay")
                }
                .buttonStyle(.bigAction(.secondary))
                .accessibilityIdentifier("setup-skip-pay")
            }
            Button(action: advance) {
                Text("Continue")
            }
            .buttonStyle(.bigAction(.primary))
            .accessibilityIdentifier("setup-continue")
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(Color.hoursCanvas)
    }

    private func advance() {
        let answers = answers
        settingsStore.update { answers.apply(to: &$0) }
        if step == .holidays {
            applyHolidayChoice()
            preselectFromCountry()
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.snappy) { step = next }
    }

    /// The country's holidays as the preview would tick them. Coming back
    /// and choosing again replaces the earlier choice; choosing none adds
    /// nothing, and is an answer, so the calendar does not ask again.
    private func applyHolidayChoice() {
        let chosen = holidayCountry.flatMap { PublicHolidayCatalog.set(country: $0, region: holidayRegion) }
        let added = settingsStore.settings.publicHolidays.addedSetID
        guard chosen?.id != added else { return }
        if added != nil {
            PublicHolidayActions.removeAdded(context: modelContext, settingsStore: settingsStore)
        }
        if let chosen {
            PublicHolidayActions.add(
                chosen, selection: chosen.defaultSelection, context: modelContext, settingsStore: settingsStore
            )
        } else {
            settingsStore.update { $0.publicHolidays.offerDismissed = true }
        }
    }

    /// The report language and the currency the country suggests, unless
    /// either was already picked by hand.
    private func preselectFromCountry() {
        var suggested = answers
        suggested.preselect(
            country: holidayCountry,
            region: holidayRegion,
            settings: settingsBefore,
            deviceCurrency: AppSettings.deviceCurrencyCode
        )
        if !languageWasChosen { answers.reportLanguage = suggested.reportLanguage }
        if !currencyWasChosen { answers.currencyCode = suggested.currencyCode }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.snappy) { step = previous }
    }
}

/// One screen of the setup: a large title, a line saying why it is asked,
/// and the question as a native form (design v2). The title is the first
/// row rather than the navigation bar's, so a long one wraps instead of
/// being cut short.
struct SetupPage<Content: View>: View {
    let heading: LocalizedStringKey
    let message: LocalizedStringKey
    /// For the UI test, which cannot read the translated title.
    let identifier: String
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Metrics.small) {
                    Text(heading)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: Metrics.tiny, bottom: Metrics.small, trailing: Metrics.tiny))
                .listRowBackground(Color.clear)
            }
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier(identifier)
    }
}
