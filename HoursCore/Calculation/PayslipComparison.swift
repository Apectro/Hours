import Foundation

// "Check your payslip" (1.2): what a payslip says for a month, typed in, beside
// what the app worked out for it. Only the figures typed in are compared, and
// each becomes a line: the app's figure, the payslip's, the difference, and
// whether that is within a tolerance. Nothing here is new arithmetic — the
// app's side is read from the same resolved days and earnings Insights shows.

/// An amount of absence as a payslip prints it: hours, or days.
struct PayslipQuantity: Hashable, Codable, Sendable {
    enum Unit: String, Codable, CaseIterable, Hashable, Sendable {
        case hours
        case days
    }

    var unit: Unit
    /// Minutes for hours; hundredths of a day for days, so 1.5 days is 150
    /// and nothing typed is ever a binary fraction.
    var amount: Int

    static func hours(_ minutes: Int) -> PayslipQuantity { PayslipQuantity(unit: .hours, amount: minutes) }
    static func days(_ hundredths: Int) -> PayslipQuantity { PayslipQuantity(unit: .days, amount: hundredths) }

    /// In minutes, reading a day as `dayMinutes`. Nil for days when there is
    /// no working day to read them by.
    func minutes(dayMinutes: Int) -> Int? {
        switch unit {
        case .hours:
            return amount
        case .days:
            guard dayMinutes > 0 else { return nil }
            // Half up, in whole minutes.
            return (amount * dayMinutes + 50) / 100
        }
    }
}

/// What the payslip says for one month, as the user typed it. Every field is
/// optional: a payslip that only lists overtime is checked for overtime.
///
/// Stored in `AppSettings.payslipChecks` under the month's `payslipKey`, and
/// decoded leniently field by field, as every setting is.
struct PayslipEntry: Hashable, Codable, Sendable {
    var workedMinutes: Int?
    var overtimeMinutes: Int?
    var sick: PayslipQuantity?
    var leave: PayslipQuantity?
    var grossCents: Int?

    init(
        workedMinutes: Int? = nil,
        overtimeMinutes: Int? = nil,
        sick: PayslipQuantity? = nil,
        leave: PayslipQuantity? = nil,
        grossCents: Int? = nil
    ) {
        self.workedMinutes = workedMinutes
        self.overtimeMinutes = overtimeMinutes
        self.sick = sick
        self.leave = leave
        self.grossCents = grossCents
    }

    var isEmpty: Bool {
        workedMinutes == nil && overtimeMinutes == nil && sick == nil && leave == nil && grossCents == nil
    }

    private enum CodingKeys: String, CodingKey {
        case workedMinutes, overtimeMinutes, sick, leave, grossCents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            workedMinutes: container.lenientOptional(.workedMinutes, Int.self),
            overtimeMinutes: container.lenientOptional(.overtimeMinutes, Int.self),
            sick: container.lenientOptional(.sick, PayslipQuantity.self),
            leave: container.lenientOptional(.leave, PayslipQuantity.self),
            grossCents: container.lenientOptional(.grossCents, Int.self)
        )
    }
}

/// The app's own figures for the month, the side a payslip is checked
/// against.
struct PayslipFigures: Hashable, Sendable {
    /// Time worked, as Insights' "Worked".
    var workedMinutes: Int
    /// Insights' "Overtime". Nil when the app does not calculate overtime —
    /// the balance is off, or "Calculate overtime" is — and the line is then
    /// not offered.
    var overtimeMinutes: Int?
    /// Hours credited on Sick days.
    var sickMinutes: Int
    /// Hours credited on Vacation days.
    var leaveMinutes: Int
    /// What the month earned. Nil while no job has a rate, and the gross pay
    /// line is then not offered.
    var earningsCents: Int?
    /// The average working day, which days typed in are read by.
    var dayMinutes: Int

    init(
        workedMinutes: Int,
        overtimeMinutes: Int?,
        sickMinutes: Int,
        leaveMinutes: Int,
        earningsCents: Int?,
        dayMinutes: Int
    ) {
        self.workedMinutes = workedMinutes
        self.overtimeMinutes = overtimeMinutes
        self.sickMinutes = sickMinutes
        self.leaveMinutes = leaveMinutes
        self.earningsCents = earningsCents
        self.dayMinutes = dayMinutes
    }

    /// From the days `PeriodEngine` resolved for the month and its summary
    /// and earnings, all counted through the same day — exactly what the
    /// Insights month shows.
    init(
        days: [DayComputation],
        summary: PeriodSummary,
        earnings: EarningsSummary?,
        settings: AppSettings,
        month: YearMonth,
        calendar: Calendar,
        countingThrough: CalendarDate?
    ) {
        func credited(_ type: DayTypeID) -> Int {
            days
                .filter { month.contains($0.date) && $0.dayType.id == type && $0.counts(through: countingThrough) }
                .reduce(0) { $0 + $1.creditedMinutes }
        }
        let features = settings.features
        let lastDay = month.lastDay(in: calendar)
        let measuredOn = countingThrough.map { min($0, lastDay) }.flatMap { month.contains($0) ? $0 : nil } ?? lastDay
        self.init(
            workedMinutes: summary.workedMinutes,
            overtimeMinutes: features.showsBalance && features.autoCalculateOvertime ? summary.overtimeMinutes : nil,
            sickMinutes: credited(.sick),
            leaveMinutes: credited(.vacation),
            earningsCents: earnings?.totalCents,
            dayMinutes: settings.averageWorkingDayMinutes(on: measuredOn)
        )
    }

    /// Whether a line can be compared at all, so the form only asks for what
    /// the app has an answer to.
    func offers(_ item: PayslipLine.Item) -> Bool {
        switch item {
        case .worked, .sick, .leave: return true
        case .overtime: return overtimeMinutes != nil
        case .gross: return earningsCents != nil
        }
    }
}

/// One figure checked: what the app says, what the payslip says.
struct PayslipLine: Hashable, Identifiable, Sendable {
    enum Item: String, CaseIterable, Hashable, Sendable {
        case worked, overtime, sick, leave, gross
    }

    enum Kind: Hashable, Sendable {
        /// Values in minutes.
        case duration
        /// Values in cents.
        case money
    }

    enum Status: Hashable, Sendable {
        case match
        case moreOnPayslip
        case lessOnPayslip
    }

    var item: Item
    var appValue: Int
    var payslipValue: Int
    /// The days typed in, in hundredths, when the payslip gave days; the
    /// value above is them in minutes.
    var payslipHundredthDays: Int?

    var id: Item { item }
    var kind: Kind { item == .gross ? .money : .duration }

    /// The payslip less the app: negative when the payslip shows less.
    var difference: Int { payslipValue - appValue }

    var status: Status {
        let tolerance = kind == .money ? PayslipComparison.moneyTolerance : PayslipComparison.durationTolerance
        if abs(difference) <= tolerance { return .match }
        return difference > 0 ? .moreOnPayslip : .lessOnPayslip
    }
}

/// A month's payslip checked against the app.
struct PayslipComparison: Hashable, Sendable {
    /// A quarter of an hour either way: payroll rounds, and so may the app.
    static let durationTolerance = 15
    /// One unit of the currency either way.
    static let moneyTolerance = 100

    var lines: [PayslipLine]
    /// The working day days were read by.
    var dayMinutes: Int

    init(entry: PayslipEntry, figures: PayslipFigures) {
        dayMinutes = figures.dayMinutes
        var lines: [PayslipLine] = []
        func add(_ item: PayslipLine.Item, app: Int?, payslip: Int?, days: Int? = nil) {
            guard let app, let payslip else { return }
            lines.append(PayslipLine(item: item, appValue: app, payslipValue: payslip, payslipHundredthDays: days))
        }
        func absence(_ item: PayslipLine.Item, app: Int, quantity: PayslipQuantity?) {
            guard let quantity else { return }
            add(
                item,
                app: app,
                payslip: quantity.minutes(dayMinutes: figures.dayMinutes),
                days: quantity.unit == .days ? quantity.amount : nil
            )
        }
        add(.worked, app: figures.workedMinutes, payslip: entry.workedMinutes)
        add(.overtime, app: figures.overtimeMinutes, payslip: entry.overtimeMinutes)
        absence(.sick, app: figures.sickMinutes, quantity: entry.sick)
        absence(.leave, app: figures.leaveMinutes, quantity: entry.leave)
        add(.gross, app: figures.earningsCents, payslip: entry.grossCents)
        self.lines = lines
    }

    var differences: [PayslipLine] { lines.filter { $0.status != .match } }
    var differenceCount: Int { differences.count }
    /// Something was compared and all of it agrees.
    var allMatch: Bool { !lines.isEmpty && differences.isEmpty }

    // MARK: - For payroll

    /// A short plain-text note for payroll, in the export language: a title,
    /// a line per figure, and a request to check when anything differs.
    ///
    ///     Payslip check · October 2026
    ///     Overtime: my records 6h · payslip 2h · difference −4h
    ///     Sick leave: my records 16h · payslip 2 × 8h = 16h · matches
    func summaryText(
        monthTitle: String,
        language: ExportLanguage,
        duration: DurationFormatting,
        money: MoneyFormatting
    ) -> String {
        let colon = language.resolved == .french ? " : " : ": "
        let decimalSeparator = language.locale.decimalSeparator ?? "."
        var text = ["\(language(.payslipCheck)) · \(monthTitle)"]
        for line in lines {
            let app = Self.value(line.appValue, kind: line.kind, duration: duration, money: money)
            var payslip = Self.value(line.payslipValue, kind: line.kind, duration: duration, money: money)
            if let days = line.payslipHundredthDays {
                let count = PayslipInput.text(hundredthDays: days, decimalSeparator: decimalSeparator)
                payslip = "\(count) × \(duration.string(dayMinutes)) = \(payslip)"
            }
            let verdict: String
            switch line.status {
            case .match:
                verdict = language(.matches)
            case .moreOnPayslip, .lessOnPayslip:
                verdict = "\(language(.difference)) "
                    + Self.signed(line.difference, kind: line.kind, duration: duration, money: money)
            }
            text.append(
                "\(Self.label(line.item, in: language))\(colon)"
                    + "\(language(.myRecords)) \(app) · \(language(.payslip)) \(payslip) · \(verdict)"
            )
        }
        if differenceCount > 0 { text.append(language(.pleaseCheck)) }
        return text.joined(separator: "\n")
    }

    static func label(_ item: PayslipLine.Item, in language: ExportLanguage) -> String {
        switch item {
        case .worked: return language(ExportTerm.worked)
        case .overtime: return language(ExportTerm.overtime)
        case .sick: return language(ExportTerm.sickLeave)
        case .leave: return language(ExportTerm.vacation)
        case .gross: return language(PayslipTerm.grossPay)
        }
    }

    private static func value(_ value: Int, kind: PayslipLine.Kind, duration: DurationFormatting, money: MoneyFormatting) -> String {
        switch kind {
        case .duration: return duration.string(value)
        case .money: return money.string(value)
        }
    }

    /// "+2h", "−4h", "−€45.00": the sign in front of the amount, the minus
    /// the typographic one, whatever the currency's own shape.
    static func signed(_ value: Int, kind: PayslipLine.Kind, duration: DurationFormatting, money: MoneyFormatting) -> String {
        let sign = value > 0 ? "+" : value < 0 ? "\u{2212}" : ""
        return sign + Self.value(abs(value), kind: kind, duration: duration, money: money)
    }
}

/// Reading what is typed into the payslip form, and writing it back.
enum PayslipInput {
    /// More hours than any month has, so a slip of the thumb stops here.
    static let maximumMinutes = 1_000 * 60
    static let maximumHundredthDays = 100 * 100

    /// "168", "7,5", "7.25" as hours; "171:30" as hours and minutes. Nil
    /// for nothing, or anything else.
    static func minutes(from text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
                  let hours = Int(parts[0]), let minutes = Int(parts[1]), minutes < 60 else { return nil }
            return min(hours * 60 + minutes, maximumMinutes)
        }
        guard let hours = ExtraWorkQuantity.parse(cleaned) else { return nil }
        return min(rounded(hours * 60), maximumMinutes)
    }

    /// "2", "1,5", "0.25" days, in hundredths.
    static func hundredthDays(from text: String) -> Int? {
        guard let days = ExtraWorkQuantity.parse(text) else { return nil }
        return min(rounded(days * 100), maximumHundredthDays)
    }

    /// "2.345,67", "2345.6", "€ 1 200" in cents. Nil when no digit was typed.
    static func cents(from text: String) -> Int? {
        guard text.contains(where: { $0.isASCII && $0.isNumber }) else { return nil }
        return MoneyInput.cents(from: text)
    }

    /// What a field opens on: whole and simple fractions of hours as a
    /// decimal ("7,5"), anything else as hours and minutes ("1:40").
    static func text(minutes: Int, decimalSeparator: String) -> String {
        if minutes % 15 == 0 {
            return ExtraWorkQuantity.string(Decimal(minutes) / 60, decimalSeparator: decimalSeparator)
        }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    static func text(hundredthDays: Int, decimalSeparator: String) -> String {
        ExtraWorkQuantity.string(Decimal(hundredthDays) / 100, decimalSeparator: decimalSeparator)
    }

    static func text(cents: Int, decimalSeparator: String) -> String {
        MoneyFormatting.plain(cents, decimalSeparator: decimalSeparator)
    }

    private static func rounded(_ value: Decimal) -> Int {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, 0, .plain)
        return max(0, NSDecimalNumber(decimal: result).intValue)
    }
}

extension YearMonth {
    /// "2026-10": the key a month's payslip is stored under.
    var payslipKey: String { String(format: "%04d-%02d", year, month) }
}

extension AppSettings {
    /// What was typed from the month's payslip, if anything.
    func payslipEntry(for month: YearMonth) -> PayslipEntry? {
        payslipChecks[month.payslipKey]
    }

    /// Stores the month's payslip; an empty one removes the month.
    mutating func setPayslipEntry(_ entry: PayslipEntry, for month: YearMonth) {
        payslipChecks[month.payslipKey] = entry.isEmpty ? nil : entry
    }
}

/// One month's entry in the stored dictionary, read without failing the rest:
/// an entry that cannot be read at all, or reads as nothing, is left out.
struct LenientPayslipEntry: Decodable {
    var entry: PayslipEntry?

    init(from decoder: Decoder) throws {
        let entry = try? PayslipEntry(from: decoder)
        self.entry = entry?.isEmpty == false ? entry : nil
    }
}
