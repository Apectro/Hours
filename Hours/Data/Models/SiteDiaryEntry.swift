import Foundation
import SwiftData

/// A stored site diary for one site and date. Mirrors `SiteDiary`,
/// decomposed into primitives.
///
/// One row per (`siteID`, `dateKey`) is a rule `SiteDiaryRepository`
/// enforces, as `SiteRepository` does for site days. Not tied to the site day
/// row: a diary can exist with no hours written, and outlives them.
@Model
final class SiteDiaryEntry {
    var siteID: String = ""
    var dateKey: Int = 0
    /// `DiaryWeather` raw value; `nil` when none was picked.
    var weatherRawValue: String?
    var temperatureCelsius: Int?
    var workDone: String = ""
    var deliveries: String = ""
    var problems: String = ""
    var visitors: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(diary: SiteDiary) {
        self.siteID = diary.siteID.uuidString
        self.dateKey = diary.date.key
        self.createdAt = Date()
        self.updatedAt = Date()
        apply(diary)
    }
}

extension SiteDiaryEntry {
    var diary: SiteDiary {
        SiteDiary(
            siteID: UUID(uuidString: siteID) ?? UUID(),
            date: CalendarDate(key: dateKey) ?? CalendarDate(year: 1970, month: 1, day: 1),
            weather: weatherRawValue.flatMap(DiaryWeather.init(rawValue:)),
            temperatureCelsius: temperatureCelsius,
            workDone: workDone,
            deliveries: deliveries,
            problems: problems,
            visitors: visitors
        )
    }

    func apply(_ diary: SiteDiary) {
        weatherRawValue = diary.weather?.rawValue
        temperatureCelsius = diary.temperatureCelsius
        workDone = diary.workDone
        deliveries = diary.deliveries
        problems = diary.problems
        visitors = diary.visitors
        updatedAt = Date()
    }

    var identity: SiteDayIdentity {
        SiteDayIdentity(siteID: siteID, dateKey: dateKey)
    }
}

/// A photo in a site's diary. The JPEG lives outside the database file
/// (`.externalStorage`), so the store stays small and a fetch of the rows
/// for the month grid never reads an image.
@Model
final class SiteDiaryPhotoEntry {
    /// `DiaryPhoto.id`, as `uuidString`. Unique by rule.
    var photoID: String = ""
    var siteID: String = ""
    var dateKey: Int = 0
    var sortOrder: Int = 0
    /// A small JPEG with no location in it; see `DiaryPhotoProcessor`.
    @Attribute(.externalStorage) var jpegData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(photo: DiaryPhoto) {
        self.photoID = photo.id.uuidString
        self.siteID = photo.siteID.uuidString
        self.dateKey = photo.date.key
        self.sortOrder = photo.sortOrder
        self.jpegData = photo.jpegData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension SiteDiaryPhotoEntry {
    /// Reads the image. Only where the bytes are wanted: a backup, a
    /// thumbnail, the PDF.
    var photo: DiaryPhoto {
        DiaryPhoto(
            id: UUID(uuidString: photoID) ?? UUID(),
            siteID: UUID(uuidString: siteID) ?? UUID(),
            date: CalendarDate(key: dateKey) ?? CalendarDate(year: 1970, month: 1, day: 1),
            sortOrder: sortOrder,
            jpegData: jpegData ?? Data()
        )
    }

    /// Where it sits, without touching the image.
    var reference: DiaryPhotoReference {
        DiaryPhotoReference(
            id: UUID(uuidString: photoID) ?? UUID(),
            date: CalendarDate(key: dateKey) ?? CalendarDate(year: 1970, month: 1, day: 1),
            sortOrder: sortOrder
        )
    }
}

/// A crew member's signature under their hours for one site and month.
/// Mirrors `CrewSignature`; the strokes are JSON, as a site day's attendance
/// list is, because they have no identity outside the signature.
@Model
final class CrewSignatureEntry {
    var siteID: String = ""
    var memberID: String = ""
    /// `yyyyMM`.
    var monthKey: Int = 0
    /// `yyyyMMdd`, the day it was signed.
    var signedOnKey: Int = 0
    var fingerprint: String = ""
    /// JSON-encoded `[[SignaturePoint]]`.
    var strokesData: Data?
    var aspectRatio: Double = 3
    var updatedAt: Date = Date()

    init(signature: CrewSignature) {
        self.siteID = signature.siteID.uuidString
        self.memberID = signature.memberID.uuidString
        self.monthKey = signature.month.year * 100 + signature.month.month
        self.updatedAt = Date()
        apply(signature)
    }
}

extension CrewSignatureEntry {
    var signature: CrewSignature {
        CrewSignature(
            siteID: UUID(uuidString: siteID) ?? UUID(),
            memberID: UUID(uuidString: memberID) ?? UUID(),
            month: YearMonth(year: monthKey / 100, month: monthKey % 100),
            signedOn: CalendarDate(key: signedOnKey) ?? CalendarDate(year: 1970, month: 1, day: 1),
            fingerprint: fingerprint,
            strokes: strokesData.flatMap { try? JSONDecoder().decode([[SignaturePoint]].self, from: $0) } ?? [],
            aspectRatio: aspectRatio
        )
    }

    /// Signing again replaces the drawing, the date and the fingerprint.
    func apply(_ signature: CrewSignature) {
        signedOnKey = signature.signedOn.key
        fingerprint = signature.fingerprint
        strokesData = try? JSONEncoder().encode(signature.strokes)
        aspectRatio = signature.aspectRatio
        updatedAt = Date()
    }

    /// One signature per person, site and month.
    var identity: String { "\(siteID)|\(memberID)|\(monthKey)" }
}
