import Foundation
import SwiftData

/// A stored site. Mirrors `Site`, decomposed into primitives.
///
/// Identifiers are kept as strings rather than `UUID`s so the row is made of
/// nothing but text, numbers and flags, like every other model here. The
/// site's identity is `siteID`, unique by rule rather than by constraint for
/// the same reason as `DayEntry.dateKey`: CloudKit refuses a unique
/// constraint, and two offline devices can produce two rows whatever the
/// schema says.
@Model
final class SiteEntry {
    /// `Site.id`, as `uuidString`.
    var siteID: String = ""
    var name: String = ""
    /// `Site.jobID`, as `uuidString`. `nil` means the default job.
    var jobID: String?
    var isArchived: Bool = false
    var sortOrder: Int = 0
    /// `Site.allowanceByDefault`. Added in schema V8 with a default, so a
    /// site written before it gives no allowance by default.
    var allowanceByDefault: Bool = false

    // Added in schema V8 for the opt-in arrival reminder (1.2): `Site`'s
    // `latitude`, `longitude`, `arrivalRadius` and `remindsOnArrival`. Where
    // the site is, how close counts as arrived (metres) and whether to
    // remind on arrival. `site` reads them and `apply` writes them, so a
    // restore (`SiteRepository.replaceAll`, which builds entries from
    // `Site`) keeps them.
    var latitude: Double?
    var longitude: Double?
    var arrivalRadius: Double = 150
    var remindsOnArrival: Bool = false

    var updatedAt: Date = Date()

    init(site: Site) {
        self.siteID = site.id.uuidString
        self.updatedAt = Date()
        apply(site)
    }
}

extension SiteEntry {
    /// The value-type view of this entry, as handed to the engine.
    ///
    /// A damaged identifier degrades the way the engine's lenient decoding
    /// does: a missing site id becomes a fresh one and a missing job id means
    /// the default job. Neither is ever written by the app, but a launch is
    /// not the place to find out that one was.
    var site: Site {
        Site(
            id: UUID(uuidString: siteID) ?? UUID(),
            name: name,
            jobID: jobID.flatMap(UUID.init(uuidString:)),
            isArchived: isArchived,
            sortOrder: sortOrder,
            allowanceByDefault: allowanceByDefault,
            latitude: latitude,
            longitude: longitude,
            arrivalRadius: arrivalRadius,
            remindsOnArrival: remindsOnArrival
        )
    }

    /// Copies a site onto this entry. `siteID` is never changed: it is the
    /// row's identity, and a different site is a different row.
    func apply(_ site: Site) {
        name = site.name
        jobID = site.jobID?.uuidString
        isArchived = site.isArchived
        sortOrder = site.sortOrder
        allowanceByDefault = site.allowanceByDefault
        latitude = site.latitude
        longitude = site.longitude
        arrivalRadius = site.arrivalRadius
        remindsOnArrival = site.remindsOnArrival
        updatedAt = Date()
    }
}
