import Foundation

/// A minimal ZIP writer.
///
/// Entries are stored uncompressed, which every ZIP reader — including the
/// OOXML readers in Excel, Numbers and LibreOffice — accepts. It exists so the
/// app can write a real `.xlsx` without taking on a third-party dependency,
/// which would undercut the point of a private, self-contained app.
struct ZIPArchive {
    private struct Entry {
        let name: String
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var payload = Data()
    private var entries: [Entry] = []
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(modified: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: modified)
        // Bound to a named local each. Written as one expression per field it
        // is a chain of shifts, masks and nil-coalescings over a literal type
        // the compiler has to pick, and it gives up trying: whether it happens
        // to finish depends on the compiler's mood, and on Linux it does not.
        // The DOS date field only has seven bits for the year.
        let year: Int = min(max((parts.year ?? 1980) - 1980, 0), 127)
        let month: Int = parts.month ?? 1
        let day: Int = parts.day ?? 1
        let hour: Int = parts.hour ?? 0
        let minute: Int = parts.minute ?? 0
        // Two-second resolution is all the DOS time field has.
        let second: Int = (parts.second ?? 0) / 2

        dosDate = UInt16(year << 9 | month << 5 | day)
        dosTime = UInt16(hour << 11 | minute << 5 | second)
    }

    mutating func addFile(name: String, contents: Data) {
        let nameBytes = Data(name.utf8)
        let crc = CRC32.checksum(contents)
        let offset = UInt32(payload.count)

        payload.appendUInt32(0x0403_4B50)      // local file header
        payload.appendUInt16(20)               // version needed
        payload.appendUInt16(0)                // flags
        payload.appendUInt16(0)                // method: stored
        payload.appendUInt16(dosTime)
        payload.appendUInt16(dosDate)
        payload.appendUInt32(crc)
        payload.appendUInt32(UInt32(contents.count))
        payload.appendUInt32(UInt32(contents.count))
        payload.appendUInt16(UInt16(nameBytes.count))
        payload.appendUInt16(0)                // extra field length
        payload.append(nameBytes)
        payload.append(contents)

        entries.append(Entry(name: name, crc: crc, size: UInt32(contents.count), offset: offset))
    }

    func finalized() -> Data {
        var archive = payload
        let directoryOffset = UInt32(archive.count)

        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            archive.appendUInt32(0x0201_4B50)  // central directory header
            archive.appendUInt16(20)           // version made by
            archive.appendUInt16(20)           // version needed
            archive.appendUInt16(0)            // flags
            archive.appendUInt16(0)            // method: stored
            archive.appendUInt16(dosTime)
            archive.appendUInt16(dosDate)
            archive.appendUInt32(entry.crc)
            archive.appendUInt32(entry.size)
            archive.appendUInt32(entry.size)
            archive.appendUInt16(UInt16(nameBytes.count))
            archive.appendUInt16(0)            // extra field length
            archive.appendUInt16(0)            // comment length
            archive.appendUInt16(0)            // disk number start
            archive.appendUInt16(0)            // internal attributes
            archive.appendUInt32(0)            // external attributes
            archive.appendUInt32(entry.offset)
            archive.append(nameBytes)
        }

        let directorySize = UInt32(archive.count) - directoryOffset

        archive.appendUInt32(0x0605_4B50)      // end of central directory
        archive.appendUInt16(0)                // this disk
        archive.appendUInt16(0)                // disk with central directory
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt32(directorySize)
        archive.appendUInt32(directoryOffset)
        archive.appendUInt16(0)                // comment length

        return archive
    }
}

/// CRC-32, as ZIP requires.
enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
            }
            return value
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
