import Foundation
import SwiftData

/// One defect on a site, in the store (schema V11). Mirrors `Defect`. The
/// rules a CloudKit-mirrored store sets hold: a default or optional on every
/// attribute, nothing `.unique`, no relationships — the site is an id
/// string, and one row per id is `DefectRepository`'s rule, kept by the same
/// last-edit-wins collapse as every other entity.
@Model
final class DefectEntry {
    /// `Defect.id`, as `uuidString`. Unique by rule.
    var defectID: String = ""
    var siteID: String = ""
    var what: String = ""
    var floor: String = ""
    var room: String = ""
    /// `DefectAssignee.kind`: "", "you" or "person".
    var assigneeKind: String = ""
    var assigneeName: String = ""
    /// Who noticed it; empty for you.
    var notedBy: String = ""
    var notedAt: Date = Date()
    /// `DefectState` raw value. One this version does not know reads as open.
    var stateRawValue: String = "open"
    var fixedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(defect: Defect) {
        self.defectID = defect.id.uuidString
        self.siteID = defect.siteID.uuidString
        self.createdAt = Date()
        apply(defect)
        self.updatedAt = defect.updatedAt
    }
}

extension DefectEntry {
    var defect: Defect {
        Defect(
            id: UUID(uuidString: defectID) ?? UUID(),
            siteID: UUID(uuidString: siteID) ?? UUID(),
            what: what,
            floor: floor,
            room: room,
            assignee: DefectAssignee(kind: assigneeKind, name: assigneeName),
            notedBy: notedBy,
            notedAt: notedAt,
            state: DefectState(storedValue: stateRawValue),
            fixedAt: fixedAt,
            updatedAt: updatedAt
        )
    }

    /// Everything but which defect it is and on which site.
    func apply(_ defect: Defect) {
        what = defect.what
        floor = defect.floor
        room = defect.room
        assigneeKind = defect.assignee.kind
        assigneeName = defect.assignee.name
        notedBy = defect.notedBy
        notedAt = defect.notedAt
        stateRawValue = defect.state.rawValue
        fixedAt = defect.fixedAt
        updatedAt = defect.updatedAt
    }
}

/// A photo of a defect (schema V11): the JPEG kept outside the database
/// file, as the diary's are, so listing a site's defects never reads an
/// image; the marks lie over it as JSON (`[DefectMark]`), never burned in.
@Model
final class DefectPhotoEntry {
    /// `DefectPhoto.id`, as `uuidString`. Unique by rule.
    var photoID: String = ""
    var defectID: String = ""
    var siteID: String = ""
    var sortOrder: Int = 0
    /// Taken after the fix.
    var isAfter: Bool = false
    /// JSON `[DefectMark]`, normalised to the photo.
    var marksData: Data?
    var takenAt: Date = Date()
    @Attribute(.externalStorage) var jpegData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(photo: DefectPhoto) {
        self.photoID = photo.id.uuidString
        self.defectID = photo.defectID.uuidString
        self.siteID = photo.siteID.uuidString
        self.sortOrder = photo.sortOrder
        self.isAfter = photo.isAfter
        self.marksData = DefectPhotoEntry.encode(photo.marks)
        self.takenAt = photo.takenAt
        self.jpegData = photo.jpegData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension DefectPhotoEntry {
    /// The photo with its bytes. Reading `jpegData` loads the file.
    var photo: DefectPhoto {
        DefectPhoto(
            id: UUID(uuidString: photoID) ?? UUID(),
            defectID: UUID(uuidString: defectID) ?? UUID(),
            siteID: UUID(uuidString: siteID) ?? UUID(),
            sortOrder: sortOrder,
            isAfter: isAfter,
            marks: marks,
            takenAt: takenAt,
            jpegData: jpegData ?? Data()
        )
    }

    var marks: [DefectMark] {
        guard let marksData else { return [] }
        return (try? JSONDecoder().decode([DefectMark].self, from: marksData)) ?? []
    }

    func setMarks(_ marks: [DefectMark]) {
        marksData = DefectPhotoEntry.encode(marks)
        updatedAt = Date()
    }

    static func encode(_ marks: [DefectMark]) -> Data? {
        marks.isEmpty ? nil : try? JSONEncoder().encode(marks)
    }
}
