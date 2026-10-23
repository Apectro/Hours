import Foundation

/// A point of a drawn signature, in a box one unit high: `x` runs from 0 to
/// the box's `aspectRatio`, `y` from 0 at the top to 1 at the bottom. Kept
/// as numbers rather than an image, so it prints sharp at any size and a
/// backup carries a few hundred numbers instead of a picture.
struct SignaturePoint: Hashable, Codable, Sendable {
    var x: Double
    var y: Double
}

/// One person's signature under their hours for one site and month.
///
/// Signed on your phone, by them, after reading their days. `fingerprint`
/// is what their hours were at that moment (`SignatureFingerprint`), so a
/// change afterwards can be shown rather than silently signed for.
struct CrewSignature: Hashable, Codable, Sendable {
    var siteID: UUID
    /// A `CrewMember.id`, or `CrewMember.youID`.
    var memberID: UUID
    var month: YearMonth
    var signedOn: CalendarDate
    var fingerprint: String
    /// Each stroke is one touch from finger down to finger up.
    var strokes: [[SignaturePoint]]
    /// Width over height of the box it was drawn in.
    var aspectRatio: Double

    init(
        siteID: UUID,
        memberID: UUID,
        month: YearMonth,
        signedOn: CalendarDate,
        fingerprint: String,
        strokes: [[SignaturePoint]],
        aspectRatio: Double = 3
    ) {
        self.siteID = siteID
        self.memberID = memberID
        self.month = month
        self.signedOn = signedOn
        self.fingerprint = fingerprint
        self.strokes = strokes
        self.aspectRatio = aspectRatio
    }

    /// Whether a drawing is enough to count as a signature: at least one
    /// stroke that actually moved. A tap is not a signature.
    static func isSignature(_ strokes: [[SignaturePoint]]) -> Bool {
        strokes.contains { stroke in
            guard let first = stroke.first else { return false }
            return stroke.contains { abs($0.x - first.x) + abs($0.y - first.y) > 0.02 }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case siteID, memberID, month, signedOn, fingerprint, strokes, aspectRatio
    }

    /// Lenient, as everything in a backup is: damaged strokes cost the
    /// drawing, never the record that the person signed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            siteID: container.lenient(.siteID, UUID()),
            memberID: container.lenient(.memberID, UUID()),
            month: container.lenient(.month, YearMonth(year: 1970, month: 1)),
            signedOn: container.lenient(.signedOn, CalendarDate(year: 1970, month: 1, day: 1)),
            fingerprint: container.lenient(.fingerprint, ""),
            strokes: container.lenient(.strokes, []),
            aspectRatio: container.lenient(.aspectRatio, 3)
        )
    }
}

/// What one person's hours on a site came to over a month, reduced to a short
/// string that changes whenever any of them does.
///
/// Every day they were present, in date order: start, end, break and the
/// minutes worked. Another person's hours, and other months, are not in it.
/// FNV-1a rather than a cryptographic hash because it only has to notice a
/// change, it has to give the same answer on Linux and on a phone, and
/// Foundation alone has no SHA on both.
enum SignatureFingerprint {
    static func make(memberID: UUID, results: [SiteDayResult], month: YearMonth) -> String {
        // One result per date, as the sheet reads them.
        var byDate: [CalendarDate: SiteDayResult] = [:]
        for result in results where month.contains(result.day.date) && byDate[result.day.date] == nil {
            byDate[result.day.date] = result
        }
        let parts = byDate.keys.sorted().compactMap { date -> String? in
            guard let person = byDate[date]?.people.first(where: { $0.memberID == memberID }) else { return nil }
            let start = person.start.map { String($0.minutes) } ?? "x"
            let end = person.end.map { String($0.minutes) } ?? "x"
            return "\(date.key):\(start)-\(end)-\(person.breakMinutes)-\(person.workedMinutes)"
        }
        return "v1:" + hex(fnv1a(parts.joined(separator: ";")))
    }

    private static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 16 - digits.count)) + digits
    }
}

/// Where a person's sign-off stands for a month.
enum SignOffState: Hashable, Sendable {
    case unsigned
    case signed(CalendarDate)
    /// Signed, and their hours have changed since.
    case changedAfterSigning(CalendarDate)
}

enum SignOff {
    /// The month the sign-off opens on when nothing else says which: the
    /// month just gone during the first ten days of a month, when its sheet
    /// is being handed in, and this month after that, when crews sign at the
    /// end of it on site.
    static func defaultMonth(today: CalendarDate) -> YearMonth {
        today.day <= 10 ? today.yearMonth.adding(months: -1) : today.yearMonth
    }

    /// The person's latest signature for the month and where it stands
    /// against their hours now.
    ///
    /// - Parameter siteID: when given, signatures for other sites are ignored.
    static func state(
        for memberID: UUID,
        signatures: [CrewSignature],
        results: [SiteDayResult],
        month: YearMonth,
        siteID: UUID? = nil
    ) -> SignOffState {
        guard let latest = latest(for: memberID, in: signatures, month: month, siteID: siteID) else {
            return .unsigned
        }
        let now = SignatureFingerprint.make(memberID: memberID, results: results, month: month)
        return now == latest.fingerprint ? .signed(latest.signedOn) : .changedAfterSigning(latest.signedOn)
    }

    /// The most recent signature, should there be several: signing again
    /// replaces, and sync can briefly hold two.
    static func latest(
        for memberID: UUID,
        in signatures: [CrewSignature],
        month: YearMonth,
        siteID: UUID? = nil
    ) -> CrewSignature? {
        signatures
            .filter { $0.memberID == memberID && $0.month == month && (siteID == nil || $0.siteID == siteID) }
            .max { $0.signedOn < $1.signedOn }
    }
}

/// One person's box in the sign-off on the director's sheet.
struct ReportSignOff: Hashable, Sendable {
    var memberID: UUID
    var name: String
    /// Their month's hours, as the sheet's total writes them.
    var hours: String
    /// "signed 31 Oct 2026", "changed after signing · signed …", or empty
    /// for a line still to sign on.
    var status: String
    var isChanged: Bool
    var strokes: [[SignaturePoint]]
    var aspectRatio: Double
}
