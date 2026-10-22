import Foundation
import SwiftData

/// The stored shape as it was before the app could sync.
///
/// Frozen. Nothing in here is ever edited again — it exists so that a store
/// written by a build from before CloudKit can be opened by one from after,
/// and its only job is to describe the *storage*, not the behaviour. The
/// mapping to `DayRecord`, the shift decoding and everything else live on the
/// current models and are deliberately absent here.
///
/// The one difference from V2, and the whole reason this file exists: both
/// entities carried `@Attribute(.unique)`. CloudKit refuses a store that has
/// one, so removing it was unavoidable — and removing a uniqueness constraint
/// changes the entity's version hash, which is a migration whether or not
/// anyone writes one down. This writes it down.
enum HoursSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DayEntry.self, HolidayRecord.self]
    }

    @Model
    final class DayEntry {
        @Attribute(.unique) var dateKey: Int = 0

        var dayTypeRawValue: String?
        var shiftsData: Data?
        var startMinutes: Int?
        var endMinutes: Int?
        var breaksData: Data?

        var manualWorkedMinutes: Int?
        var expectedOverrideMinutes: Int?
        var manualBalanceMinutes: Int?
        var adjustmentMinutes: Int = 0
        var adjustmentReasonRawValue: String = "correction"

        var note: String = ""
        var locationName: String = ""
        var tagsJoined: String = ""

        var isIncluded: Bool = true
        var timeZoneIdentifier: String?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(dateKey: Int) {
            self.dateKey = dateKey
        }
    }

    @Model
    final class HolidayRecord {
        @Attribute(.unique) var identifier: UUID = UUID()
        var name: String = ""

        var kindRawValue: String = "annual"
        var year: Int = 2000
        var month: Int = 1
        var day: Int = 1
        var weekday: Int = 2
        var ordinal: Int = 1
        var startYear: Int?
        var endYear: Int?

        var countsAsWorkingDay: Bool = false
        var isEnabled: Bool = true
        var notes: String = ""
        var createdAt: Date = Date()

        init(identifier: UUID) {
            self.identifier = identifier
        }
    }
}

/// The stored shape from the day the app could sync until it learned about
/// sites: V1's columns, with uniqueness moved out of the schema and into
/// `WorkdayRepository`.
///
/// Frozen, like V1. Until V3 these were the live top-level classes, and that
/// was fine while V2 was the newest version. It stops being fine the moment
/// the live classes can change: a version must describe exactly what stores
/// written by it hold, and if V2 kept pointing at `DayEntry` the next edit to
/// `DayEntry` would silently rewrite what "V2" means, leaving every real V2
/// store matching no version at all. So these are copies of the live classes
/// as they stood, column for column, type for type, optionality for
/// optionality — which is everything a version hash is made of. The class
/// names are irrelevant to it; the entity names are the unqualified ones,
/// `DayEntry` and `HolidayRecord`, as before. `MigrationTests` writes a
/// store with the live classes and opens it through the plan, which is what
/// proves the copies match.
enum HoursSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DayEntry.self, HolidayRecord.self]
    }

    @Model
    final class DayEntry {
        var dateKey: Int = 0

        var dayTypeRawValue: String?
        var shiftsData: Data?
        var startMinutes: Int?
        var endMinutes: Int?
        var breaksData: Data?

        var manualWorkedMinutes: Int?
        var expectedOverrideMinutes: Int?
        var manualBalanceMinutes: Int?
        var adjustmentMinutes: Int = 0
        var adjustmentReasonRawValue: String = "correction"

        var note: String = ""
        var locationName: String = ""
        var tagsJoined: String = ""

        var isIncluded: Bool = true
        var timeZoneIdentifier: String?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(dateKey: Int) {
            self.dateKey = dateKey
        }
    }

    @Model
    final class HolidayRecord {
        var identifier: UUID = UUID()
        var name: String = ""

        var kindRawValue: String = "annual"
        var year: Int = 2000
        var month: Int = 1
        var day: Int = 1
        var weekday: Int = 2
        var ordinal: Int = 1
        var startYear: Int?
        var endYear: Int?

        var countsAsWorkingDay: Bool = false
        var isEnabled: Bool = true
        var notes: String = ""
        var createdAt: Date = Date()

        init(identifier: UUID) {
            self.identifier = identifier
        }
    }
}

/// The stored shape from sites until the site diary: V2's two entities,
/// plus sites, their crews and the days worked on them.
///
/// Frozen, for the reason V2 is: until V4 these were the live top-level
/// classes, and a version must keep describing exactly what stores written
/// by it hold. Copies of the five classes as they stood, column for column.
enum HoursSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DayEntry.self, HolidayRecord.self, SiteEntry.self, CrewMemberEntry.self, SiteDayEntry.self]
    }

    @Model
    final class DayEntry {
        var dateKey: Int = 0

        var dayTypeRawValue: String?
        var shiftsData: Data?
        var startMinutes: Int?
        var endMinutes: Int?
        var breaksData: Data?

        var manualWorkedMinutes: Int?
        var expectedOverrideMinutes: Int?
        var manualBalanceMinutes: Int?
        var adjustmentMinutes: Int = 0
        var adjustmentReasonRawValue: String = "correction"

        var note: String = ""
        var locationName: String = ""
        var tagsJoined: String = ""

        var isIncluded: Bool = true
        var timeZoneIdentifier: String?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(dateKey: Int) {
            self.dateKey = dateKey
        }
    }

    @Model
    final class HolidayRecord {
        var identifier: UUID = UUID()
        var name: String = ""

        var kindRawValue: String = "annual"
        var year: Int = 2000
        var month: Int = 1
        var day: Int = 1
        var weekday: Int = 2
        var ordinal: Int = 1
        var startYear: Int?
        var endYear: Int?

        var countsAsWorkingDay: Bool = false
        var isEnabled: Bool = true
        var notes: String = ""
        var createdAt: Date = Date()

        init(identifier: UUID) {
            self.identifier = identifier
        }
    }

    @Model
    final class SiteEntry {
        var siteID: String = ""
        var name: String = ""
        var jobID: String?
        var isArchived: Bool = false
        var sortOrder: Int = 0
        var updatedAt: Date = Date()

        init(siteID: String) {
            self.siteID = siteID
        }
    }

    @Model
    final class CrewMemberEntry {
        var memberID: String = ""
        var siteID: String = ""
        var name: String = ""
        var isHidden: Bool = false
        var sortOrder: Int = 0
        var updatedAt: Date = Date()

        init(memberID: String) {
            self.memberID = memberID
        }
    }

    @Model
    final class SiteDayEntry {
        var siteID: String = ""
        var dateKey: Int = 0

        var startMinutes: Int?
        var endMinutes: Int?
        var breakMinutes: Int = 0

        var presentData: Data?

        var note: String = ""
        var jobID: String?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(siteID: String, dateKey: Int) {
            self.siteID = siteID
            self.dateKey = dateKey
        }
    }
}

/// The stored shape from the site diary until extra work: V3's five
/// entities, a bad-weather flag on the site day, and the site diary, its
/// photos and the crew's signatures.
///
/// Frozen, for the reason V2 and V3 are: until V5 these were the live
/// top-level classes. Copies of the eight classes as they stood, column for
/// column, the photo's external storage included.
enum HoursSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            DayEntry.self, HolidayRecord.self, SiteEntry.self, CrewMemberEntry.self, SiteDayEntry.self,
            SiteDiaryEntry.self, SiteDiaryPhotoEntry.self, CrewSignatureEntry.self
        ]
    }

    @Model
    final class DayEntry {
        var dateKey: Int = 0

        var dayTypeRawValue: String?
        var shiftsData: Data?
        var startMinutes: Int?
        var endMinutes: Int?
        var breaksData: Data?

        var manualWorkedMinutes: Int?
        var expectedOverrideMinutes: Int?
        var manualBalanceMinutes: Int?
        var adjustmentMinutes: Int = 0
        var adjustmentReasonRawValue: String = "correction"

        var note: String = ""
        var locationName: String = ""
        var tagsJoined: String = ""

        var isIncluded: Bool = true
        var timeZoneIdentifier: String?

        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(dateKey: Int) {
            self.dateKey = dateKey
        }
    }

    @Model
    final class HolidayRecord {
        var identifier: UUID = UUID()
        var name: String = ""

        var kindRawValue: String = "annual"
        var year: Int = 2000
        var month: Int = 1
        var day: Int = 1
        var weekday: Int = 2
        var ordinal: Int = 1
        var startYear: Int?
        var endYear: Int?

        var countsAsWorkingDay: Bool = false
        var isEnabled: Bool = true
        var notes: String = ""
        var createdAt: Date = Date()

        init(identifier: UUID) {
            self.identifier = identifier
        }
    }

    @Model
    final class SiteEntry {
        var siteID: String = ""
        var name: String = ""
        var jobID: String?
        var isArchived: Bool = false
        var sortOrder: Int = 0
        var updatedAt: Date = Date()

        init(siteID: String) {
            self.siteID = siteID
        }
    }

    @Model
    final class CrewMemberEntry {
        var memberID: String = ""
        var siteID: String = ""
        var name: String = ""
        var isHidden: Bool = false
        var sortOrder: Int = 0
        var updatedAt: Date = Date()

        init(memberID: String) {
            self.memberID = memberID
        }
    }

    @Model
    final class SiteDayEntry {
        var siteID: String = ""
        var dateKey: Int = 0

        var startMinutes: Int?
        var endMinutes: Int?
        var breakMinutes: Int = 0

        var presentData: Data?

        var note: String = ""
        var jobID: String?
        var isBadWeatherStop: Bool = false

        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(siteID: String, dateKey: Int) {
            self.siteID = siteID
            self.dateKey = dateKey
        }
    }

    @Model
    final class SiteDiaryEntry {
        var siteID: String = ""
        var dateKey: Int = 0
        var weatherRawValue: String?
        var temperatureCelsius: Int?
        var workDone: String = ""
        var deliveries: String = ""
        var problems: String = ""
        var visitors: String = ""
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(siteID: String, dateKey: Int) {
            self.siteID = siteID
            self.dateKey = dateKey
        }
    }

    @Model
    final class SiteDiaryPhotoEntry {
        var photoID: String = ""
        var siteID: String = ""
        var dateKey: Int = 0
        var sortOrder: Int = 0
        @Attribute(.externalStorage) var jpegData: Data?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(photoID: String) {
            self.photoID = photoID
        }
    }

    @Model
    final class CrewSignatureEntry {
        var siteID: String = ""
        var memberID: String = ""
        var monthKey: Int = 0
        var signedOnKey: Int = 0
        var fingerprint: String = ""
        var strokesData: Data?
        var aspectRatio: Double = 3
        var updatedAt: Date = Date()

        init(siteID: String, memberID: String, monthKey: Int) {
            self.siteID = siteID
            self.memberID = memberID
            self.monthKey = monthKey
        }
    }
}

/// The stored shape now: V4's eight entities and extra work — jobs, their
/// photos, the reports that were sent and the remembered items — each with a
/// default or an optional on every property, nothing unique and no
/// relationships, so a CloudKit-mirrored store accepts them.
///
/// The models themselves stay at the top level rather than nested in here, so
/// that the rest of the app says `DayEntry` and not `HoursSchemaV5.DayEntry`.
/// When V6 comes, this gets frozen copies the way V4 did.
enum HoursSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            DayEntry.self, HolidayRecord.self, SiteEntry.self, CrewMemberEntry.self, SiteDayEntry.self,
            SiteDiaryEntry.self, SiteDiaryPhotoEntry.self, CrewSignatureEntry.self,
            ExtraWorkJobEntry.self, ExtraWorkPhotoEntry.self, ExtraWorkReportEntry.self, ExtraWorkItemEntry.self
        ]
    }
}

/// How a store gets from one version to the next.
///
/// Every stage is lightweight, because nothing about existing data changes.
/// V1 to V2 keeps every column's name and type and only drops a constraint;
/// V2 to V3 only adds three entities, each with a default on every property;
/// V3 to V4 adds one column with a default to the site day, and three
/// entities with a default on every property; V4 to V5 adds four entities
/// with a default on every property.
/// There is nothing to transform, and a custom stage would only be somewhere
/// for a bug to live.
///
/// It is declared rather than left to inference for two reasons. SwiftData's
/// automatic migration is a best effort with no promise attached, and this is
/// the one change in the app's history that could lose somebody's year of
/// hours if that effort failed. And a declared plan can be tested, which is
/// what `MigrationTests` does.
enum HoursMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [HoursSchemaV1.self, HoursSchemaV2.self, HoursSchemaV3.self, HoursSchemaV4.self, HoursSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: HoursSchemaV1.self,
        toVersion: HoursSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: HoursSchemaV2.self,
        toVersion: HoursSchemaV3.self
    )

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: HoursSchemaV3.self,
        toVersion: HoursSchemaV4.self
    )

    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: HoursSchemaV4.self,
        toVersion: HoursSchemaV5.self
    )
}
