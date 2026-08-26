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

/// The stored shape now: the same columns, with uniqueness moved out of the
/// schema and into `WorkdayRepository`.
///
/// The models themselves stay at the top level rather than nested in here, so
/// that the rest of the app says `DayEntry` and not `HoursSchemaV2.DayEntry`.
enum HoursSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [DayEntry.self, HolidayRecord.self]
    }
}

/// How a store gets from one to the other.
///
/// Lightweight, because nothing about the data changes — every column keeps its
/// name and its type, and only a constraint is dropped. There is nothing to
/// transform, and a custom stage would only be somewhere for a bug to live.
///
/// It is declared rather than left to inference for two reasons. SwiftData's
/// automatic migration is a best effort with no promise attached, and this is
/// the one change in the app's history that could lose somebody's year of
/// hours if that effort failed. And a declared plan can be tested, which is
/// what `MigrationTests` does.
enum HoursMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [HoursSchemaV1.self, HoursSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: HoursSchemaV1.self,
        toVersion: HoursSchemaV2.self
    )
}
