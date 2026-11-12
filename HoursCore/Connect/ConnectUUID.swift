import Foundation

/// The protocol's name-based ids (RFC 9562 version 5, SHA-1), for the two app
/// records that have no UUID of their own: a site day is keyed by site and
/// date, a sign-off by site, person and month. The server computes the same
/// id from the same key and refuses one that differs (`idMismatch`), so this
/// must match `packages/protocol/src/uuid5.ts` byte for byte.
///
/// SHA-1 is written out here because the engine builds on Linux, where
/// CryptoKit does not exist. It names records; it protects nothing.
enum ConnectUUID {
    /// The namespace every Zeitkonto Connect name-based id is made in.
    static let namespace = UUID(uuidString: "6f1f3c55-1a52-4b8e-9d64-2c0e7a4b9a10")!

    /// A version 5 UUID for `name` in `namespace`.
    static func v5(_ name: String, namespace: UUID = ConnectUUID.namespace) -> UUID {
        var input = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        input.append(contentsOf: Array(name.utf8))
        var hash = Array(sha1(input).prefix(16))
        hash[6] = (hash[6] & 0x0f) | 0x50
        hash[8] = (hash[8] & 0x3f) | 0x80
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]
        ))
    }

    /// One site day per site and date.
    static func siteDayID(siteID: UUID, date: CalendarDate) -> UUID {
        v5(["siteDay", ConnectID.string(siteID), ConnectFormat.date(date)].joined(separator: ":"))
    }

    /// One sign-off per site, person and month. The person is the company's
    /// (`ConnectPeople.personID`), never the app's "You".
    static func signOffID(siteID: UUID, memberID: UUID, month: YearMonth) -> UUID {
        v5(["signOff", ConnectID.string(siteID), ConnectID.string(memberID), ConnectFormat.month(month)].joined(separator: ":"))
    }

    /// Ids the app makes for things the protocol keys by id but the app does
    /// not: an assignment of a person the phone added, a crew row made for a
    /// person from the web, a file made from a record (a signature drawn as
    /// a picture). Name-based, so two phones on the same iCloud make the same
    /// row, and a retry asks for the same file.
    static func assignmentID(siteID: UUID, personID: UUID) -> UUID {
        v5(["assignment", ConnectID.string(siteID), ConnectID.string(personID)].joined(separator: ":"))
    }

    static func crewRowID(siteID: UUID, personID: UUID) -> UUID {
        v5(["crewRow", ConnectID.string(siteID), ConnectID.string(personID)].joined(separator: ":"))
    }

    static func fileID(_ purpose: String, of recordID: UUID, version: String = "") -> UUID {
        v5(["file", purpose, ConnectID.string(recordID), version].joined(separator: ":"))
    }

    // MARK: - SHA-1

    static func sha1(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x6745_2301
        var h1: UInt32 = 0xEFCD_AB89
        var h2: UInt32 = 0x98BA_DCFE
        var h3: UInt32 = 0x1032_5476
        var h4: UInt32 = 0xC3D2_E1F0

        var bytes = message
        let bitLength = UInt64(message.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var w = [UInt32](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: bytes.count, by: 64) {
            for i in 0..<16 {
                let at = chunk + i * 4
                let b0 = UInt32(bytes[at]) << 24
                let b1 = UInt32(bytes[at + 1]) << 16
                let b2 = UInt32(bytes[at + 2]) << 8
                w[i] = b0 | b1 | b2 | UInt32(bytes[at + 3])
            }
            for i in 16..<80 {
                let x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = (x << 1) | (x >> 31)
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | (~b & d)
                    k = 0x5A82_7999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9_EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1B_BCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62_C1D6
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = temp
            }
            h0 = h0 &+ a
            h1 = h1 &+ b
            h2 = h2 &+ c
            h3 = h3 &+ d
            h4 = h4 &+ e
        }
        var out: [UInt8] = []
        for value in [h0, h1, h2, h3, h4] {
            out.append(UInt8(truncatingIfNeeded: value >> 24))
            out.append(UInt8(truncatingIfNeeded: value >> 16))
            out.append(UInt8(truncatingIfNeeded: value >> 8))
            out.append(UInt8(truncatingIfNeeded: value))
        }
        return out
    }

    /// A short, stable fingerprint of some bytes, for "has this record
    /// changed since it was last queued". Hex SHA-1.
    static func digest(_ data: Data) -> String {
        sha1(Array(data)).map { byte in
            let hex = String(byte, radix: 16)
            return byte < 16 ? "0" + hex : hex
        }.joined()
    }
}

/// How the protocol writes the app's values.
enum ConnectFormat {
    /// `YYYY-MM-DD`.
    static func date(_ date: CalendarDate) -> String {
        [pad(date.year, 4), pad(date.month, 2), pad(date.day, 2)].joined(separator: "-")
    }

    /// `YYYY-MM`.
    static func month(_ month: YearMonth) -> String {
        [pad(month.year, 4), pad(month.month, 2)].joined(separator: "-")
    }

    /// `HH:MM`.
    static func time(_ time: TimeOfDay) -> String {
        [pad(time.hour, 2), pad(time.minute, 2)].joined(separator: ":")
    }

    static func parseDate(_ text: String?) -> CalendarDate? {
        guard let parts = text?.split(separator: "-"), parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return CalendarDate(year: year, month: month, day: day)
    }

    static func parseMonth(_ text: String?) -> YearMonth? {
        guard let parts = text?.split(separator: "-"), parts.count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        return YearMonth(year: year, month: month)
    }

    static func parseTime(_ text: String?) -> TimeOfDay? {
        guard let parts = text?.split(separator: ":"), parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return TimeOfDay(hour: hour, minute: minute)
    }

    /// ISO 8601 with Z, to the second.
    static func moment(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func parseMoment(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// A decimal string with a point and at most three decimals: "45.5",
    /// "12". Never a float, never a comma.
    static func quantity(_ value: Decimal) -> String {
        var rounded = Decimal()
        var input = value < 0 ? Decimal(0) : value
        NSDecimalRound(&rounded, &input, 3, .plain)
        let text = NSDecimalNumber(decimal: rounded).description(withLocale: Locale(identifier: "en_US_POSIX"))
        return text
    }

    static func parseQuantity(_ text: String) -> Decimal? {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
    }
}
