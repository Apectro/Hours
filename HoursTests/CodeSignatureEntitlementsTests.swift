import XCTest
@testable import Hours

/// Reading the entitlements a binary was signed with, out of its own code
/// signature. This is what lets the app know, before it opens a syncing
/// store, that the build really carries iCloud — the 1.0 crash was a build
/// that did not, opening one anyway.
///
/// The binaries here are built byte by byte from the layout in Apple's
/// `<mach-o/loader.h>` and `<kern/cs_blobs.h>`: a 64-bit Mach-O header, its
/// load commands, and an `LC_CODE_SIGNATURE` pointing at a big-endian
/// SuperBlob whose slot 5 is the entitlements plist.
final class CodeSignatureEntitlementsTests: XCTestCase {
    private let ourContainer = "iCloud.app.zeitkonto"

    private func plist(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>\(body)</dict></plist>
        """.utf8)
    }

    private var syncingEntitlements: Data {
        plist("""
        <key>application-identifier</key><string>ABCDE12345.app.zeitkonto.hours</string>
        <key>aps-environment</key><string>production</string>
        <key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.app.zeitkonto</string></array>
        <key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>
        <key>com.apple.security.application-groups</key><array><string>group.app.zeitkonto</string></array>
        """)
    }

    // MARK: - Reading the signature

    func testEntitlementsAreReadFromAThinBinary() throws {
        let binary = MachOFixture.thin(entitlements: syncingEntitlements)
        guard case .signed(let xml) = CodeSignatureEntitlements.read(binary) else {
            return XCTFail("a signed binary read as \(CodeSignatureEntitlements.read(binary))")
        }
        XCTAssertEqual(xml, syncingEntitlements)
    }

    func testEntitlementsAreReadFromTheArm64SliceOfAFatBinary() throws {
        let slice = MachOFixture.thin(entitlements: syncingEntitlements)
        let binary = MachOFixture.fat(slices: [(MachOFixture.cpuX86_64, MachOFixture.thin(entitlements: nil)), (MachOFixture.cpuARM64, slice)])
        XCTAssertEqual(CodeSignatureEntitlements.read(binary), .signed(entitlements: syncingEntitlements))
    }

    func testOffsetsCountFromTheStartOfTheFileNotOfTheDataIndices() {
        // A slice of a larger buffer does not start at index 0; reading it
        // must not copy it first to find out where it starts.
        let binary = MachOFixture.thin(entitlements: syncingEntitlements)
        let sliced = (Data(repeating: 0xEE, count: 5) + binary).dropFirst(5)
        XCTAssertEqual(sliced.startIndex, 5)
        XCTAssertEqual(CodeSignatureEntitlements.read(sliced), .signed(entitlements: syncingEntitlements))
    }

    func testABinaryWithNoSignatureIsUnsigned() {
        // What `CODE_SIGNING_ALLOWED=NO` produces: the CI simulator builds.
        XCTAssertEqual(CodeSignatureEntitlements.read(MachOFixture.thin(signature: false)), .notSigned)
    }

    func testASignatureWithNoEntitlementsSlotHasNone() {
        XCTAssertEqual(CodeSignatureEntitlements.read(MachOFixture.thin(entitlements: nil)), .signed(entitlements: nil))
    }

    func testAnythingThatIsNotAMachOIsUnreadable() {
        XCTAssertEqual(CodeSignatureEntitlements.read(Data()), .unreadable)
        XCTAssertEqual(CodeSignatureEntitlements.read(Data("#!/bin/sh\necho hello\n".utf8)), .unreadable)
    }

    func testATruncatedBinaryIsUnreadableRatherThanACrash() {
        let whole = MachOFixture.thin(entitlements: syncingEntitlements)
        // Every length short of the whole: none may trap, and none may claim
        // entitlements it could not read in full.
        for length in stride(from: 0, to: whole.count, by: 7) {
            let result = CodeSignatureEntitlements.read(whole.prefix(length))
            XCTAssertNotEqual(result, .signed(entitlements: syncingEntitlements), "length \(length)")
        }
    }

    func testASignatureOffsetPastTheEndIsUnreadable() {
        var binary = MachOFixture.thin(entitlements: syncingEntitlements)
        // dataoff of LC_CODE_SIGNATURE, the second load command, at 32 + 24 + 8.
        binary.replaceSubrange(64..<68, with: MachOFixture.little(UInt32.max))
        XCTAssertEqual(CodeSignatureEntitlements.read(binary), .unreadable)
    }

    // MARK: - What the entitlements say about iCloud

    func testABuildSignedForOurContainerCanSync() {
        let reading = CodeSignatureEntitlements.Reading.signed(entitlements: syncingEntitlements)
        XCTAssertEqual(ICloudEntitlement.status(of: reading, container: ourContainer), .present)
    }

    func testAnUnsignedBuildCannotSync() {
        XCTAssertEqual(ICloudEntitlement.status(of: .notSigned, container: ourContainer), .missing)
    }

    func testASignedBuildWithoutICloudCannotSync() {
        // The 1.0 TestFlight build: signed, with the App Group and nothing else.
        let reading = CodeSignatureEntitlements.Reading.signed(entitlements: plist("""
        <key>com.apple.security.application-groups</key><array><string>group.app.zeitkonto</string></array>
        """))
        XCTAssertEqual(ICloudEntitlement.status(of: reading, container: ourContainer), .missing)
        XCTAssertEqual(ICloudEntitlement.status(of: .signed(entitlements: nil), container: ourContainer), .missing)
    }

    func testAnotherContainerIsNotOurs() {
        let reading = CodeSignatureEntitlements.Reading.signed(entitlements: plist("""
        <key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.app.somebody-else</string></array>
        <key>com.apple.developer.icloud-services</key><array><string>CloudKit</string></array>
        """))
        XCTAssertEqual(ICloudEntitlement.status(of: reading, container: ourContainer), .missing)
    }

    func testDocumentsWithoutCloudKitIsNotEnough() {
        let reading = CodeSignatureEntitlements.Reading.signed(entitlements: plist("""
        <key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.app.zeitkonto</string></array>
        <key>com.apple.developer.icloud-services</key><array><string>CloudDocuments</string></array>
        """))
        XCTAssertEqual(ICloudEntitlement.status(of: reading, container: ourContainer), .missing)
    }

    func testAWildcardServiceListCoversCloudKit() {
        let reading = CodeSignatureEntitlements.Reading.signed(entitlements: plist("""
        <key>com.apple.developer.icloud-container-identifiers</key><array><string>iCloud.app.zeitkonto</string></array>
        <key>com.apple.developer.icloud-services</key><string>*</string>
        """))
        XCTAssertEqual(ICloudEntitlement.status(of: reading, container: ourContainer), .present)
    }

    func testEntitlementsThatAreNotAPlistAreUnreadable() {
        let reading = CodeSignatureEntitlements.Reading.signed(entitlements: Data("not a plist".utf8))
        XCTAssertEqual(ICloudEntitlement.status(of: reading, container: ourContainer), .unreadable)
        XCTAssertEqual(ICloudEntitlement.status(of: .unreadable, container: ourContainer), .unreadable)
    }
}

/// Mach-O binaries built by hand, as `ld` and `codesign` lay them out.
enum MachOFixture {
    static let cpuARM64: UInt32 = 0x0100_000C
    static let cpuX86_64: UInt32 = 0x0100_0007

    static func little(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    static func big(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    /// A thin 64-bit executable: header, an `LC_UUID`, then (if signed) an
    /// `LC_CODE_SIGNATURE` whose blob holds a stand-in CodeDirectory and,
    /// if given, the entitlements.
    static func thin(signature: Bool = true, entitlements: Data? = nil) -> Data {
        let uuidCommand = little(0x1B) + little(24) + Data(repeating: 0xAB, count: 16)
        let signatureCommandSize: UInt32 = signature ? 16 : 0
        let commandsSize = UInt32(uuidCommand.count) + signatureCommandSize
        let headerSize: UInt32 = 32
        let codeOffset = (headerSize + commandsSize + 15) / 16 * 16
        let code = Data(repeating: 0x1F, count: 64)
        let signatureOffset = codeOffset + UInt32(code.count)

        var blob = Data()
        if signature {
            // A CodeDirectory's contents do not matter here; its presence does.
            let directory = big(0xFADE_0C02) + big(12) + big(0)
            var slots: [(type: UInt32, blob: Data)] = [(0, directory)]
            if let entitlements {
                slots.append((5, big(0xFADE_7171) + big(UInt32(8 + entitlements.count)) + entitlements))
            }
            let indexSize = UInt32(12 + 8 * slots.count)
            var offset = indexSize
            var index = Data()
            var payload = Data()
            for slot in slots {
                index += big(slot.type) + big(offset)
                payload += slot.blob
                offset += UInt32(slot.blob.count)
            }
            blob = big(0xFADE_0CC0) + big(offset) + big(UInt32(slots.count)) + index + payload
        }

        var binary = little(0xFEED_FACF) + little(cpuARM64) + little(0) + little(2)
            + little(signature ? 2 : 1) + little(commandsSize) + little(0) + little(0)
        binary += uuidCommand
        if signature {
            binary += little(0x1D) + little(16) + little(signatureOffset) + little(UInt32(blob.count))
        }
        binary += Data(repeating: 0, count: Int(codeOffset) - binary.count)
        binary += code
        binary += blob
        return binary
    }

    /// A universal binary: the big-endian fat header and one slice per CPU.
    static func fat(slices: [(cpu: UInt32, binary: Data)]) -> Data {
        let align: UInt32 = 12  // 4096
        var header = big(0xCAFE_BABE) + big(UInt32(slices.count))
        var body = Data()
        var offset = UInt32(4096)
        for slice in slices {
            header += big(slice.cpu) + big(0) + big(offset) + big(UInt32(slice.binary.count)) + big(align)
            var padded = slice.binary
            padded += Data(repeating: 0, count: (4096 - padded.count % 4096) % 4096)
            body += padded
            offset += UInt32(padded.count)
        }
        header += Data(repeating: 0, count: 4096 - header.count)
        return header + body
    }
}
