import SwiftUI

/// A tip at the top of a screen (2026-11-05): a lightbulb in the accent,
/// a short bold title, one sentence, an action when there is something to
/// do, and ✕, which hides it for good. A list row of its own, in the
/// system's grouped row background like every other row: no shadow, no
/// gradient, no border.
///
/// VoiceOver reads "Tip: title. sentence" as one element; the action and ✕
/// are separate buttons. Which tip a screen shows is the engine's
/// (`TipAdvisor`); ✕ goes through `SettingsStore`, so it is synced and
/// backed up.
struct TipCard: View {
    let tip: TipID
    /// The action's button, when the tip has one.
    var action: (() -> Void)?

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.medium) {
            Image(systemName: "lightbulb")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Metrics.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: tip.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(verbatim: tip.message)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: tip.spokenText))
                .accessibilityIdentifier("tip-\(tip.identifier)")

                if let action, let title = tip.actionTitle {
                    Button(action: action) {
                        Text(verbatim: title)
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 32, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    // Borderless, so the row's buttons each take only their
                    // own tap.
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("tip-\(tip.identifier)-action")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    settingsStore.update { $0.tips.dismiss(tip) }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.hoursSecondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            // The 44 pt target reaches past the text's top, as the title
            // sits under it.
            .padding(.top, -Metrics.small)
            .padding(.trailing, -Metrics.small)
            .accessibilityLabel(String(localized: "Hide this tip"))
            .accessibilityIdentifier("tip-\(tip.identifier)-dismiss")
        }
        .padding(.vertical, Metrics.tiny)
    }
}

extension TipID {
    /// The bold title.
    var title: String {
        switch self {
        case .siteWorkDays: return String(localized: "Set this site's work days", comment: "Tip title on a site with no work days set")
        case .siteDaysNotWritten: return String(localized: "Didn't work here some days?", comment: "Tip title on a site with days not written")
        case .ownerName: return String(localized: "Put your name on the sheets", comment: "Tip title on Export while your name is not set")
        case .scanMaterial: return String(localized: "Scan the box", comment: "Tip title in the extra-work editor")
        case .swipeDays: return String(localized: "Swipe a day", comment: "Tip title on the calendar's week list")
        case .defectPhotos: return String(localized: "Photo first", comment: "Tip title on an empty defects list")
        }
    }

    /// The one sentence under it.
    var message: String {
        switch self {
        case .siteWorkDays:
            return String(localized: "So the calendar and reminders know which days you work here.", comment: "Tip on a site with no work days set")
        case .siteDaysNotWritten:
            return String(localized: "Tap the red count to mark them as no work, or pause the site.", comment: "Tip on a site with days not written")
        case .ownerName:
            return String(localized: "Your name goes on every PDF you send.", comment: "Tip on Export while your name is not set")
        case .scanMaterial:
            return String(localized: "Scan a barcode to add material; name it once and it's known from then on.", comment: "Tip in the extra-work editor")
        case .swipeDays:
            return String(localized: "Swipe left on a day to delete it, right to write or edit it.", comment: "Tip on the calendar's week list")
        case .defectPhotos:
            return String(localized: "Take a photo of the problem and circle it; the PDF shows it big.", comment: "Tip on an empty defects list")
        }
    }

    /// The action's title, for the tips that have one.
    var actionTitle: String? {
        switch self {
        case .siteWorkDays: return String(localized: "Set work days", comment: "Tip action: opens the site's work days")
        case .siteDaysNotWritten: return String(localized: "Show days", comment: "Tip action: opens the days not written")
        case .ownerName: return String(localized: "Add name", comment: "Tip action: asks for your name on the sheets")
        case .scanMaterial, .swipeDays, .defectPhotos: return nil
        }
    }

    /// What VoiceOver reads: "Tip: title. sentence".
    var spokenText: String {
        String(
            localized: "Tip: \(title). \(message)",
            comment: "VoiceOver for a tip at the top of a screen; the values are its title and its sentence"
        )
    }
}
