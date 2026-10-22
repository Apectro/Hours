import Foundation

/// The entitlements a binary was signed with, read out of its own code
/// signature.
///
/// Why this exists: opening a syncing store in a build that is not signed for
/// iCloud does not throw. CloudKit raises an Objective-C exception on a queue
/// of its own, which Swift cannot catch, and the process dies — at every
/// launch, because the choice to sync is remembered. That is what happened to
/// 1.0 in TestFlight. iOS has no public call that answers "do I have this
/// entitlement?", but the answer is in the executable: `codesign` writes the
/// entitlements plist into the signature, and the signature is a documented
/// structure at the end of the file the app is running from. So the app reads
/// its own executable (`Bundle.main.executableURL`) and asks this.
///
/// Pure parsing with every offset bounds-checked: a binary this cannot make
/// sense of reads as `.unreadable`, never as a crash, and never as permission.
/// Layouts from `<mach-o/loader.h>`, `<mach-o/fat.h>` and `<kern/cs_blobs.h>`.
enum CodeSignatureEntitlements {
    enum Reading: Equatable {
        /// No `LC_CODE_SIGNATURE`: a build made with `CODE_SIGNING_ALLOWED=NO`.
        case notSigned
        /// Signed; the XML entitlements plist, or `nil` when it has none.
        case signed(entitlements: Data?)
        /// Not a Mach-O this understands, or damaged.
        case unreadable
    }

    private static let machOMagic64: UInt32 = 0xFEED_FACF
    private static let fatMagic: UInt32 = 0xCAFE_BABE
    private static let fatMagic64: UInt32 = 0xCAFE_BABF
    private static let codeSignatureCommand: UInt32 = 0x1D
    private static let superBlobMagic: UInt32 = 0xFADE_0CC0
    private static let entitlementsMagic: UInt32 = 0xFADE_7171
    private static let entitlementsSlot: UInt32 = 5
    private static let cpuARM64: UInt32 = 0x0100_000C

    static func read(_ data: Data) -> Reading {
        let bytes = Bytes(data)
        guard let magic = bytes.little32(at: 0) else { return .unreadable }
        if magic == machOMagic64 { return readThin(bytes, at: 0) }

        guard let fat = bytes.big32(at: 0), fat == fatMagic || fat == fatMagic64,
              let count = bytes.big32(at: 4), count > 0, count <= 16 else { return .unreadable }
        // The slice for the CPU we run on; there is only ever arm64 on an
        // iPhone, and anything else is a better answer than none.
        let entrySize = fat == fatMagic64 ? 32 : 20
        var chosen: Int?
        for index in 0..<Int(count) {
            let entry = 8 + index * entrySize
            guard let cpu = bytes.big32(at: entry) else { return .unreadable }
            let offset: Int?
            if fat == fatMagic64 {
                offset = bytes.big64(at: entry + 8).flatMap { $0 <= UInt64(Int.max) ? Int($0) : nil }
            } else {
                offset = bytes.big32(at: entry + 8).map(Int.init)
            }
            guard let offset else { return .unreadable }
            if chosen == nil || cpu == cpuARM64 { chosen = offset }
        }
        guard let chosen else { return .unreadable }
        return readThin(bytes, at: chosen)
    }

    private static func readThin(_ bytes: Bytes, at base: Int) -> Reading {
        guard bytes.little32(at: base) == machOMagic64,
              let commandCount = bytes.little32(at: base + 16) else { return .unreadable }
        var cursor = base + 32
        for _ in 0..<min(Int(commandCount), 10_000) {
            guard let command = bytes.little32(at: cursor),
                  let size = bytes.little32(at: cursor + 4), size >= 8 else { return .unreadable }
            if command == codeSignatureCommand {
                guard let offset = bytes.little32(at: cursor + 8),
                      let length = bytes.little32(at: cursor + 12) else { return .unreadable }
                return readSuperBlob(bytes, at: base + Int(offset), length: Int(length))
            }
            cursor += Int(size)
        }
        return .notSigned
    }

    private static func readSuperBlob(_ bytes: Bytes, at start: Int, length: Int) -> Reading {
        guard bytes.contains(start, length), bytes.big32(at: start) == superBlobMagic,
              let count = bytes.big32(at: start + 8), count <= 64 else { return .unreadable }
        for index in 0..<Int(count) {
            let entry = start + 12 + index * 8
            guard let type = bytes.big32(at: entry), let offset = bytes.big32(at: entry + 4) else { return .unreadable }
            guard type == entitlementsSlot else { continue }
            let blob = start + Int(offset)
            guard bytes.big32(at: blob) == entitlementsMagic,
                  let blobLength = bytes.big32(at: blob + 4), blobLength >= 8,
                  Int(offset) + Int(blobLength) <= length,
                  let xml = bytes.slice(blob + 8, Int(blobLength) - 8) else { return .unreadable }
            return .signed(entitlements: xml)
        }
        return .signed(entitlements: nil)
    }

    /// Bounds-checked reads, so a short or damaged file is an answer rather
    /// than a trap. Offsets are from the start of the file whatever the
    /// `Data`'s own indices are, and nothing is copied but what is asked
    /// for: the executable is memory-mapped, and reading the few pages the
    /// header and the signature live on is all this should cost at launch.
    private struct Bytes {
        let data: Data
        init(_ data: Data) { self.data = data }

        func contains(_ start: Int, _ length: Int) -> Bool {
            start >= 0 && length >= 0 && start <= data.count && length <= data.count - start
        }

        func slice(_ start: Int, _ length: Int) -> Data? {
            guard contains(start, length) else { return nil }
            let from = data.startIndex + start
            return data.subdata(in: from..<(from + length))
        }

        func little32(at offset: Int) -> UInt32? {
            slice(offset, 4).map { $0.reversed().reduce(0) { $0 << 8 | UInt32($1) } }
        }

        func big32(at offset: Int) -> UInt32? {
            slice(offset, 4).map { $0.reduce(0) { $0 << 8 | UInt32($1) } }
        }

        func big64(at offset: Int) -> UInt64? {
            slice(offset, 8).map { $0.reduce(0) { $0 << 8 | UInt64($1) } }
        }
    }
}

/// Whether a build is signed to use the app's CloudKit container.
enum ICloudEntitlement: String, Codable, Equatable {
    case present
    /// Definitely not: unsigned, or signed without iCloud for this container.
    case missing
    /// The signature could not be read, so nobody can say. Treated as missing
    /// wherever it decides anything: the cost of being wrong that way is sync
    /// not starting, and the cost of being wrong the other way is the crash.
    case unreadable

    static let containersKey = "com.apple.developer.icloud-container-identifiers"
    static let servicesKey = "com.apple.developer.icloud-services"

    static func status(of reading: CodeSignatureEntitlements.Reading, container: String) -> ICloudEntitlement {
        switch reading {
        case .unreadable:
            return .unreadable
        case .notSigned, .signed(entitlements: nil):
            return .missing
        case .signed(entitlements: let xml?):
            guard let object = try? PropertyListSerialization.propertyList(from: xml, options: [], format: nil),
                  let entitlements = object as? [String: Any] else { return .unreadable }
            let containers = entitlements[containersKey] as? [String] ?? []
            let services: [String]
            if let list = entitlements[servicesKey] as? [String] {
                services = list
            } else if let single = entitlements[servicesKey] as? String {
                services = [single]
            } else {
                services = []
            }
            let cloudKit = services.contains("CloudKit") || services.contains("*")
            return containers.contains(container) && cloudKit ? .present : .missing
        }
    }
}
