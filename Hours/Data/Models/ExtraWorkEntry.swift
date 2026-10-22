import Foundation
import SwiftData

// Extra work in the store (schema V5; V6 adds whether a job is done). Four entities, each following the rule
// a CloudKit-mirrored store needs: every attribute has a default or is
// optional, nothing is `.unique`, and there are no relationships — rows refer
// to each other by id strings, as the diary does, and uniqueness is the
// repository's rule (`ExtraWorkRepository`), kept by the same last-edit-wins
// collapse as every other entity.

/// One job of extra work. Mirrors `ExtraWorkJob`; the material, the hours
/// and the client's signature are JSON, because none has an identity
/// outside the job.
@Model
final class ExtraWorkJobEntry {
    /// `ExtraWorkJob.id`, as `uuidString`. Unique by rule.
    var jobID: String = ""
    var siteID: String = ""
    var dateKey: Int = 0
    /// `ExtraWorkJob.description`. Not called `description`, which every
    /// class already answers to.
    var workDescription: String = ""
    /// JSON-encoded `[ExtraWorkItem]`; quantities as text, so 12.5 stays 12.5.
    var itemsData: Data?
    /// JSON-encoded `[ExtraWorkHours]`; `nil` when no hours were noted.
    var hoursData: Data?
    /// JSON-encoded `ExtraWorkSignature`; `nil` when the client has not signed.
    var clientSignatureData: Data?
    /// Whether the work is finished. Stored with the default `true` on
    /// purpose: the V5→V6 migration fills the new column with it, and every
    /// job written before V6 was written as finished work. The app sets
    /// `false` itself for a new job (`apply`).
    var isDone: Bool = true
    /// When it was ticked done; `nil` in progress and for migrated jobs.
    var doneAt: Date?
    /// `ExtraWorkStatus` raw value. A V5 store may hold "invoiced", a step
    /// there is no more; it reads as sent.
    var statusRawValue: String = "open"
    var sentAt: Date?
    var sentReportID: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(job: ExtraWorkJob) {
        self.jobID = job.id.uuidString
        self.siteID = job.siteID.uuidString
        self.createdAt = job.createdAt
        self.updatedAt = job.updatedAt
        apply(job)
        self.updatedAt = job.updatedAt
    }
}

extension ExtraWorkJobEntry {
    var job: ExtraWorkJob {
        ExtraWorkJob(
            id: UUID(uuidString: jobID) ?? UUID(),
            siteID: UUID(uuidString: siteID) ?? UUID(),
            date: CalendarDate(key: dateKey) ?? CalendarDate(year: 1970, month: 1, day: 1),
            description: workDescription,
            items: itemsData.flatMap { try? JSONDecoder().decode([ExtraWorkItem].self, from: $0) } ?? [],
            hours: hoursData.flatMap { try? JSONDecoder().decode([ExtraWorkHours].self, from: $0) } ?? [],
            clientSignature: clientSignatureData.flatMap { try? JSONDecoder().decode(ExtraWorkSignature.self, from: $0) },
            isDone: isDone,
            doneAt: doneAt,
            status: ExtraWorkStatus(storedValue: statusRawValue),
            sentAt: sentAt,
            sentReportID: sentReportID.flatMap(UUID.init(uuidString:)),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Everything but which job it is and on which site: moving a job to
    /// another day is an edit; to another site is not offered.
    func apply(_ job: ExtraWorkJob) {
        dateKey = job.date.key
        workDescription = job.description
        itemsData = try? JSONEncoder().encode(job.items)
        hoursData = job.hours.isEmpty ? nil : try? JSONEncoder().encode(job.hours)
        clientSignatureData = job.clientSignature.flatMap { try? JSONEncoder().encode($0) }
        isDone = job.isDone
        doneAt = job.doneAt
        statusRawValue = job.status.rawValue
        sentAt = job.sentAt
        sentReportID = job.sentReportID?.uuidString
        updatedAt = Date()
    }
}

/// A photo on a job. The JPEG lives outside the database file, as a diary
/// photo's does, so listing jobs never reads an image.
@Model
final class ExtraWorkPhotoEntry {
    /// `ExtraWorkPhoto.id`, as `uuidString`. Unique by rule.
    var photoID: String = ""
    var jobID: String = ""
    var siteID: String = ""
    var sortOrder: Int = 0
    /// A small JPEG with no metadata in it; see `DiaryPhotoProcessor`.
    @Attribute(.externalStorage) var jpegData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(photo: ExtraWorkPhoto) {
        self.photoID = photo.id.uuidString
        self.jobID = photo.jobID.uuidString
        self.siteID = photo.siteID.uuidString
        self.sortOrder = photo.sortOrder
        self.jpegData = photo.jpegData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension ExtraWorkPhotoEntry {
    /// Reads the image: a backup, a thumbnail, the PDF.
    var photo: ExtraWorkPhoto {
        ExtraWorkPhoto(
            id: UUID(uuidString: photoID) ?? UUID(),
            jobID: UUID(uuidString: jobID) ?? UUID(),
            siteID: UUID(uuidString: siteID) ?? UUID(),
            sortOrder: sortOrder,
            jpegData: jpegData ?? Data()
        )
    }
}

/// A report that was shared: which jobs, and the client's signature under
/// all of them.
@Model
final class ExtraWorkReportEntry {
    /// `ExtraWorkReportRecord.id`, as `uuidString`. Unique by rule.
    var reportID: String = ""
    var siteID: String = ""
    var sentAt: Date = Date()
    /// JSON-encoded `[UUID]`.
    var jobIDsData: Data?
    /// JSON-encoded `ExtraWorkSignature`.
    var clientSignatureData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(record: ExtraWorkReportRecord) {
        self.reportID = record.id.uuidString
        self.siteID = record.siteID.uuidString
        self.sentAt = record.sentAt
        self.jobIDsData = try? JSONEncoder().encode(record.jobIDs)
        self.clientSignatureData = record.clientSignature.flatMap { try? JSONEncoder().encode($0) }
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension ExtraWorkReportEntry {
    var record: ExtraWorkReportRecord {
        ExtraWorkReportRecord(
            id: UUID(uuidString: reportID) ?? UUID(),
            siteID: UUID(uuidString: siteID) ?? UUID(),
            sentAt: sentAt,
            jobIDs: jobIDsData.flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? [],
            clientSignature: clientSignatureData.flatMap { try? JSONDecoder().decode(ExtraWorkSignature.self, from: $0) }
        )
    }
}

/// A remembered item for the "Used before" chips. One list for the user.
@Model
final class ExtraWorkItemEntry {
    /// `ExtraWorkCatalogItem.id`, as `uuidString`. Unique by rule, and one
    /// per name (`ExtraWorkCatalog.key`), also by rule.
    var itemID: String = ""
    var name: String = ""
    /// `ExtraWorkUnit.code`.
    var unitCode: String = "pcs"
    var useCount: Int = 0
    var lastUsed: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(item: ExtraWorkCatalogItem) {
        self.itemID = item.id.uuidString
        self.createdAt = Date()
        apply(item)
    }
}

extension ExtraWorkItemEntry {
    var item: ExtraWorkCatalogItem {
        ExtraWorkCatalogItem(
            id: UUID(uuidString: itemID) ?? UUID(),
            name: name,
            unit: ExtraWorkUnit(code: unitCode),
            useCount: useCount,
            lastUsed: lastUsed
        )
    }

    func apply(_ item: ExtraWorkCatalogItem) {
        name = item.name
        unitCode = item.unit.code
        useCount = item.useCount
        lastUsed = item.lastUsed
        updatedAt = Date()
    }
}
