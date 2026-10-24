import SwiftUI
import UIKit

/// Insights › Month: "Check your payslip", and how the month's check went —
/// "Checked ✓" or "2 differences" — against the hours as they are now.
struct PayslipCheckRow: View {
    /// Nil until the month's payslip has been typed in.
    let comparison: PayslipComparison?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            SurfaceCard {
                HStack(spacing: Metrics.medium) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Check your payslip")
                            .font(.subheadline.weight(.semibold))
                        status
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("insights-payslip-check")
    }

    @ViewBuilder
    private var status: some View {
        if let comparison, !comparison.lines.isEmpty {
            if comparison.allMatch {
                Label("Checked", systemImage: "checkmark")
                    .foregroundStyle(Color.hoursPositive)
            } else {
                Text(verbatim: String(inflected: "^[\(comparison.differenceCount) difference](inflect: true)"))
                    .foregroundStyle(Color.hoursNegative)
            }
        } else {
            Text("Compare it with your hours")
                .foregroundStyle(.secondary)
        }
    }
}

/// What the payslip says for a month, typed in, and how it compares.
///
/// One sheet, two states: the figures (Cancel and Check), then the result
/// (Done), with a note for payroll to share or copy. Opens on the result
/// when the month was checked before. Only what is typed is compared; a line
/// the app has no answer to — overtime it does not calculate, money without
/// a rate — is not asked for. See `PayslipComparison`.
struct PayslipCheckSheet: View {
    let month: YearMonth
    let monthTitle: String
    let figures: PayslipFigures
    /// What was stored when the sheet opened, so a field the form does not
    /// show is kept rather than dropped on saving.
    let stored: PayslipEntry?

    @Environment(SettingsStore.self) var settingsStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    @State private var showsResult: Bool
    @State private var worked: String
    @State private var overtime: String
    @State private var sick: String
    @State private var sickUnit: PayslipQuantity.Unit
    @State private var leave: String
    @State private var leaveUnit: PayslipQuantity.Unit
    @State private var gross: String
    @State private var copied = false
    @FocusState private var focused: PayslipLine.Item?

    init(month: YearMonth, monthTitle: String, figures: PayslipFigures, stored: PayslipEntry?) {
        self.month = month
        self.monthTitle = monthTitle
        self.figures = figures
        self.stored = stored
        let separator = Self.decimalSeparator
        func text(_ quantity: PayslipQuantity?) -> String {
            guard let quantity else { return "" }
            switch quantity.unit {
            case .hours: return PayslipInput.text(minutes: quantity.amount, decimalSeparator: separator)
            case .days: return PayslipInput.text(hundredthDays: quantity.amount, decimalSeparator: separator)
            }
        }
        _showsResult = State(initialValue: stored != nil)
        _worked = State(initialValue: stored?.workedMinutes.map { PayslipInput.text(minutes: $0, decimalSeparator: separator) } ?? "")
        _overtime = State(initialValue: stored?.overtimeMinutes.map { PayslipInput.text(minutes: $0, decimalSeparator: separator) } ?? "")
        _sick = State(initialValue: text(stored?.sick))
        _sickUnit = State(initialValue: stored?.sick?.unit ?? .hours)
        _leave = State(initialValue: text(stored?.leave))
        _leaveUnit = State(initialValue: stored?.leave?.unit ?? .hours)
        _gross = State(initialValue: stored?.grossCents.map { PayslipInput.text(cents: $0, decimalSeparator: separator) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Group {
                if showsResult {
                    result
                } else {
                    form
                }
            }
            .navigationTitle("Check your payslip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
    }

    // MARK: - Toolbar

    /// Cancel and Check over the figures, Done over the result. Each item
    /// holds a view that changes, rather than the builder choosing items.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if !showsResult {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("payslip-cancel")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if showsResult {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("payslip-done")
            } else {
                Button("Check", action: check)
                    .disabled(entry.isEmpty)
                    .accessibilityIdentifier("payslip-check")
            }
        }
    }

    // MARK: - The figures

    private var form: some View {
        Form {
            Section {
                field(.worked, String(localized: "Hours worked"), text: $worked)
                if figures.offers(.overtime) {
                    field(.overtime, String(localized: "Overtime"), text: $overtime)
                }
                field(.sick, name(of: .sick), text: $sick, unit: $sickUnit)
                field(.leave, name(of: .leave), text: $leave, unit: $leaveUnit)
                if figures.offers(.gross) {
                    field(.gross, String(localized: "Gross pay"), text: $gross)
                }
            } header: {
                Text(verbatim: String(
                    localized: "From your payslip for \(monthTitle)",
                    comment: "Payslip check, over the fields; the value is a month such as October 2026"
                ))
            } footer: {
                Text(verbatim: formFooter)
            }

            if stored != nil {
                Section {
                    Button("Remove this check", role: .destructive) {
                        settingsStore.update { $0.setPayslipEntry(PayslipEntry(), for: month) }
                        dismiss()
                    }
                    .accessibilityIdentifier("payslip-remove")
                }
            }
        }
        .onAppear { if stored == nil { focused = figures.offers(.overtime) ? .overtime : .worked } }
    }

    private var formFooter: String {
        var parts = [String(localized: "Fill in only what your payslip shows. Hours can be typed as 7.5 or 7:30.")]
        if figures.dayMinutes > 0 {
            let day = settingsStore.settings.displayFormatting.string(figures.dayMinutes)
            parts.append(String(
                localized: "A day counts as \(day).",
                comment: "Payslip check; sick days and leave typed in days are read as this many hours. The value is like 8h"
            ))
        }
        return parts.joined(separator: " ")
    }

    private func field(
        _ item: PayslipLine.Item,
        _ label: String,
        text: Binding<String>,
        unit: Binding<PayslipQuantity.Unit>? = nil
    ) -> some View {
        LabeledContent {
            HStack(spacing: Metrics.small) {
                TextField(label, text: text, prompt: Text(verbatim: "—"))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                    .focused($focused, equals: item)
                    .accessibilityIdentifier("payslip-field-\(item.rawValue)")
                if let unit {
                    Picker(selection: unit) {
                        Text("Hours").tag(PayslipQuantity.Unit.hours)
                        Text("Days").tag(PayslipQuantity.Unit.days)
                    } label: {
                        Text(verbatim: label)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("payslip-unit-\(item.rawValue)")
                }
            }
        } label: {
            Text(verbatim: label)
        }
        .frame(minHeight: 44)
    }

    /// The figures as typed, keeping what the form does not show.
    private var entry: PayslipEntry {
        func quantity(_ text: String, _ unit: PayslipQuantity.Unit) -> PayslipQuantity? {
            switch unit {
            case .hours: return PayslipInput.minutes(from: text).map(PayslipQuantity.hours)
            case .days: return PayslipInput.hundredthDays(from: text).map(PayslipQuantity.days)
            }
        }
        return PayslipEntry(
            workedMinutes: PayslipInput.minutes(from: worked),
            overtimeMinutes: figures.offers(.overtime) ? PayslipInput.minutes(from: overtime) : stored?.overtimeMinutes,
            sick: quantity(sick, sickUnit),
            leave: quantity(leave, leaveUnit),
            grossCents: figures.offers(.gross) ? PayslipInput.cents(from: gross) : stored?.grossCents
        )
    }

    private func check() {
        let entry = self.entry
        settingsStore.update { $0.setPayslipEntry(entry, for: month) }
        focused = nil
        copied = false
        withAnimation(.snappy(duration: 0.2)) { showsResult = true }
    }

    // MARK: - The result

    private var comparison: PayslipComparison { PayslipComparison(entry: entry, figures: figures) }

    private var result: some View {
        let comparison = self.comparison
        return Form {
            Section {
                if comparison.lines.isEmpty {
                    Text("Nothing to compare yet. Fill in a figure from your payslip.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(comparison.lines) { line in
                        lineRow(line)
                    }
                }
            } header: {
                Text(verbatim: monthTitle)
            } footer: {
                Text("Payroll may count differently, with other cut-off dates or averages. If you’re unsure, talk to payroll.")
            }

            Section {
                if !comparison.lines.isEmpty {
                    let note = payrollNote(comparison)
                    ShareLink(item: note) {
                        Label("Share with payroll", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("payslip-share")
                    Button {
                        UIPasteboard.general.string = note
                        copied = true
                    } label: {
                        if copied {
                            Label("Copied", systemImage: "checkmark")
                        } else {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                    .accessibilityIdentifier("payslip-copy")
                }
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showsResult = false }
                } label: {
                    Label("Edit figures", systemImage: "pencil")
                }
                .accessibilityIdentifier("payslip-edit")
            }
        }
    }

    private func lineRow(_ line: PayslipLine) -> some View {
        let stacks = dynamicTypeSize.isAccessibilitySize
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.tiny))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Metrics.medium))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name(of: line.item))
                Text(verbatim: String(
                    localized: "Recorded \(value(line.appValue, line.kind)) · payslip \(payslipValue(line))",
                    comment: "Payslip check, under a figure: the app's value, then the payslip's"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if !stacks { Spacer(minLength: Metrics.small) }
            switch line.status {
            case .match:
                Label("Matches", systemImage: "checkmark")
                    .foregroundStyle(Color.hoursPositive)
            case .moreOnPayslip:
                Text(verbatim: String(
                    localized: "Payslip shows \(value(line.difference, line.kind)) more",
                    comment: "Payslip check; the value is an amount such as 4h or €45.00"
                ))
                .foregroundStyle(Color.hoursNegative)
                .multilineTextAlignment(stacks ? .leading : .trailing)
            case .lessOnPayslip:
                Text(verbatim: String(
                    localized: "Payslip shows \(value(-line.difference, line.kind)) less",
                    comment: "Payslip check; the value is an amount such as 4h or €45.00"
                ))
                .foregroundStyle(Color.hoursNegative)
                .multilineTextAlignment(stacks ? .leading : .trailing)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(line.status == .match ? "payslip-match-\(line.item.rawValue)" : "payslip-difference-\(line.item.rawValue)")
    }

    // MARK: - Words and figures

    private func name(of item: PayslipLine.Item) -> String {
        let catalog = settingsStore.settings.dayTypeCatalog
        switch item {
        case .worked: return String(localized: "Hours worked")
        case .overtime: return String(localized: "Overtime")
        case .sick: return catalog.definition(for: .sick).displayName()
        case .leave: return catalog.definition(for: .vacation).displayName()
        case .gross: return String(localized: "Gross pay")
        }
    }

    private func value(_ amount: Int, _ kind: PayslipLine.Kind) -> String {
        switch kind {
        case .duration: return settingsStore.settings.displayFormatting.string(amount)
        case .money: return settingsStore.settings.money.string(amount)
        }
    }

    /// "16h", or "2 × 8h = 16h" when the payslip gave days.
    private func payslipValue(_ line: PayslipLine) -> String {
        let total = value(line.payslipValue, line.kind)
        guard let days = line.payslipHundredthDays else { return total }
        let count = PayslipInput.text(hundredthDays: days, decimalSeparator: Self.decimalSeparator)
        return "\(count) × \(value(figures.dayMinutes, .duration)) = \(total)"
    }

    /// The note for payroll, in the language of the reports for the boss.
    private func payrollNote(_ comparison: PayslipComparison) -> String {
        let settings = settingsStore.settings
        let language = settings.export.language
        let formatting = CalendarFormatting(locale: language.locale, calendar: settingsStore.workCalendar)
        return comparison.summaryText(
            monthTitle: formatting.monthTitle(month),
            language: language,
            duration: DurationFormatting(style: settings.displayDurationStyle, decimalSeparator: language.locale.decimalSeparator ?? "."),
            money: MoneyFormatting(
                currencyCode: settings.currencyCode(fallback: AppSettings.deviceCurrencyCode),
                locale: language.locale
            )
        )
    }

    private static var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }
}
