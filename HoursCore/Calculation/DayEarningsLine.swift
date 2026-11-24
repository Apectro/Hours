import Foundation

/// One line of "Earned this day" (2026-11-24): what part of the day's pay
/// it is, the hours it is for, the rate when there is one to name, and
/// what it comes to.
///
/// The lines are another cut of the day's `EarningsBreakdown`, never a
/// second calculation: they add up to the day's total to the cent, so the
/// days of a month add up to the month Insights shows.
struct DayEarningsLine: Hashable, Sendable, Identifiable {
    enum Kind: String, Hashable, Sendable {
        /// Hours at the rate: "8h × €12.50".
        case regular
        /// Overtime hours at the rate with its surcharge in: "1h 30m
        /// overtime × €15.63". On a day worked at two rates, the surcharge
        /// alone, with no rate.
        case overtime
        /// What Saturday, Sunday or a public holiday, and the night add on
        /// top of the rate, and the hours each was paid on.
        case saturday
        case sundayAndHoliday
        case night
        /// Credited hours of a paid day off.
        case paidAbsence
        case allowance
        case mileage
    }

    var kind: Kind
    /// The hours the line is for; nil for the allowance and kilometres.
    var minutes: Int?
    /// The hourly rate the line's hours were paid: the rate, or for
    /// overtime the rate with the surcharge in. Nil when there is no one
    /// rate to name.
    var rateCents: Int?
    /// Paid absence at less than in full: the percentage.
    var percent: Int?
    /// The kilometres line: how many.
    var kilometres: Int?
    var cents: Int

    var id: String { kind.rawValue }
}

extension DayEarnings {
    /// The day's pay as plain lines, in the order read: hours, overtime,
    /// the surcharges, paid absence, allowance, kilometres. Each only when
    /// there is something on it.
    ///
    /// With one rate and overtime, the hours are split in two: the hours
    /// that are not overtime at the rate, and the overtime hours at the rate
    /// with the surcharge in, which together are exactly the breakdown's
    /// base and overtime parts. Without one rate to name (two jobs at
    /// different rates) the hours stay one line and overtime is its
    /// surcharge, as Insights shows them.
    var lines: [DayEarningsLine] {
        var lines: [DayEarningsLine] = []
        let parts = breakdown

        if let rate = hourlyRateCents, let percent = overtimePercent,
           overtimeMinutes > 0, overtimeMinutes <= paidWorkedMinutes {
            let regularMinutes = paidWorkedMinutes - overtimeMinutes
            // Half a cent up, as the day is rounded; never more than the
            // hours earned at the rate altogether.
            let regularCents = min(parts.baseCents, (regularMinutes * rate + 30) / 60)
            if regularMinutes > 0 {
                lines.append(DayEarningsLine(kind: .regular, minutes: regularMinutes, rateCents: rate, cents: regularCents))
            }
            lines.append(DayEarningsLine(
                kind: .overtime,
                minutes: overtimeMinutes,
                rateCents: (rate * (100 + percent) + 50) / 100,
                cents: parts.baseCents + parts.overtimeCents - (regularMinutes > 0 ? regularCents : 0)
            ))
        } else {
            if paidWorkedMinutes > 0 || parts.baseCents != 0 {
                lines.append(DayEarningsLine(
                    kind: .regular, minutes: paidWorkedMinutes, rateCents: hourlyRateCents, cents: parts.baseCents
                ))
            }
            if parts.overtimeCents != 0 {
                lines.append(DayEarningsLine(kind: .overtime, minutes: overtimeMinutes, cents: parts.overtimeCents))
            }
        }

        if parts.saturdayCents != 0 {
            lines.append(DayEarningsLine(kind: .saturday, minutes: saturdayMinutes, cents: parts.saturdayCents))
        }
        if parts.sundayAndHolidayCents != 0 {
            lines.append(DayEarningsLine(
                kind: .sundayAndHoliday, minutes: sundayAndHolidayMinutes, cents: parts.sundayAndHolidayCents
            ))
        }
        if parts.nightCents != 0 {
            lines.append(DayEarningsLine(kind: .night, minutes: nightMinutes, cents: parts.nightCents))
        }
        if parts.paidAbsenceCents != 0 {
            lines.append(DayEarningsLine(
                kind: .paidAbsence, minutes: paidAbsenceMinutes, percent: absencePaidPercent, cents: parts.paidAbsenceCents
            ))
        }
        if parts.allowanceCents != 0 {
            lines.append(DayEarningsLine(kind: .allowance, cents: parts.allowanceCents))
        }
        if parts.mileageCents != 0 {
            lines.append(DayEarningsLine(kind: .mileage, kilometres: kilometres, cents: parts.mileageCents))
        }
        return lines
    }
}
