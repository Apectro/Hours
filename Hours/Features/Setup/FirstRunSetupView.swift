import SwiftUI

/// Where the setup's last screen leads.
enum FirstRunFinish: String, Identifiable {
    case writeToday
    case createSite

    var id: String { rawValue }
}

/// The three questions a fresh install asks once: your name, your week, and
/// whether your breaks are paid. One question per screen, every one of them
/// skippable, and each answer saved as you continue past it, so skipping
/// later keeps what was already answered.
struct FirstRunSetupView: View {
    /// `nil` when skipped.
    let onFinish: (FirstRunFinish?) -> Void

    @Environment(SettingsStore.self) private var settingsStore

    @State private var step: Step = .name
    @State private var answers = FirstRunAnswers(settings: AppSettings())
    @State private var hasLoaded = false

    enum Step: Int {
        case name, week, breaks, finish
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch step {
                case .name:
                    SetupNameStep(name: $answers.name, onReturn: advance)
                case .week:
                    SetupWeekStep(answers: $answers)
                case .breaks:
                    SetupBreaksStep(breaksArePaid: $answers.breaksArePaid)
                case .finish:
                    SetupFinishStep(onFinish: onFinish)
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

            if step != .finish {
                Button(action: advance) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.vertical, Metrics.large)
                .accessibilityIdentifier("setup-continue")
            }
        }
        .padding(.horizontal, Metrics.extraLarge)
        .background(Color.hoursCanvas.ignoresSafeArea())
        .onAppear {
            // Once: the answers start from the settings, and coming back to
            // this view must not throw away what has been typed.
            guard !hasLoaded else { return }
            hasLoaded = true
            answers = FirstRunAnswers(settings: settingsStore.settings)
        }
    }

    private var topBar: some View {
        HStack {
            if step == .week || step == .breaks {
                Button("Back", action: goBack)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("setup-back")
            }
            Spacer(minLength: 0)
            if step != .finish {
                Button("Skip") { onFinish(nil) }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("setup-skip")
            }
        }
        .padding(.top, Metrics.small)
    }

    private func advance() {
        let answers = answers
        settingsStore.update { answers.apply(to: &$0) }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.snappy) { step = next }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.snappy) { step = previous }
    }
}

/// One screen of the setup: a large title, a line saying why it is asked,
/// and the question.
struct SetupPage<Content: View>: View {
    let heading: LocalizedStringKey
    let message: LocalizedStringKey
    /// For the UI test, which cannot read the translated title.
    let identifier: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.large) {
                Text(heading)
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
                    .padding(.top, Metrics.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Metrics.extraLarge)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier(identifier)
    }
}
