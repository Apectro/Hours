import Foundation

/// A construction site: somewhere a crew works, recorded as one set of hours
/// per day rather than one entry per person.
struct Site: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    /// The job the site's hours count towards, if any. Days freeze this when
    /// they are written (see `SiteDay.jobID`), so re-pointing a site later
    /// never rewrites history.
    var jobID: UUID?
    /// Archived sites keep their history but stop appearing when you record
    /// a new day.
    var isArchived: Bool
    var sortOrder: Int
    /// Whoever is ticked present on a new day gets the field allowance
    /// unless it is taken off them (1.2). Off unless set; a day freezes who
    /// got it (`SiteDay.allowanceMemberIDs`), so changing this later never
    /// rewrites a day already written.
    var allowanceByDefault: Bool
    /// Where the site is, for the opt-in arrival reminder (1.2): both or
    /// neither, read through `place`. Set only from "Use my current
    /// location" in the site's settings; nothing else ever reads the phone's
    /// location, and these never leave the phone except in a backup.
    var latitude: Double?
    var longitude: Double?
    /// How close counts as arrived, in metres (`arrivalRadii`).
    var arrivalRadius: Double
    /// Whether reaching or leaving the site asks about the clock. Off unless
    /// turned on; with no `place` it watches nothing (`monitorsArrival`).
    var remindsOnArrival: Bool
    /// Where the site is in words, for the sheets (1.2): one or two lines as
    /// typed ("Kaiserstraße 12" over "10115 Berlin"), or filled in from the
    /// saved place on request. Empty means none, and nothing is printed.
    var address: String

    init(
        id: UUID = UUID(),
        name: String,
        jobID: UUID? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        allowanceByDefault: Bool = false,
        latitude: Double? = nil,
        longitude: Double? = nil,
        arrivalRadius: Double = Site.defaultArrivalRadius,
        remindsOnArrival: Bool = false,
        address: String = ""
    ) {
        self.id = id
        self.name = name
        self.jobID = jobID
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.allowanceByDefault = allowanceByDefault
        self.latitude = latitude
        self.longitude = longitude
        self.arrivalRadius = arrivalRadius
        self.remindsOnArrival = remindsOnArrival
        self.address = address
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, jobID, isArchived, sortOrder, allowanceByDefault
        case latitude, longitude, arrivalRadius, remindsOnArrival
        case address
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            name: container.lenient(.name, ""),
            jobID: container.lenientOptional(.jobID),
            isArchived: container.lenient(.isArchived, false),
            sortOrder: container.lenient(.sortOrder, 0),
            allowanceByDefault: container.lenient(.allowanceByDefault, false),
            latitude: container.lenientOptional(.latitude),
            longitude: container.lenientOptional(.longitude),
            arrivalRadius: container.lenient(.arrivalRadius, Site.defaultArrivalRadius),
            remindsOnArrival: container.lenient(.remindsOnArrival, false),
            address: container.lenient(.address, "")
        )
    }

    /// Written by hand so `allowanceByDefault`, the arrival keys and the
    /// address go in only when set, and a site without them is written exactly as before.
    /// 1.0 and 1.1 decode a site by its keys and skip these.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(jobID, forKey: .jobID)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(sortOrder, forKey: .sortOrder)
        if allowanceByDefault { try container.encode(allowanceByDefault, forKey: .allowanceByDefault) }
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        if arrivalRadius != Site.defaultArrivalRadius { try container.encode(arrivalRadius, forKey: .arrivalRadius) }
        if remindsOnArrival { try container.encode(remindsOnArrival, forKey: .remindsOnArrival) }
        if !address.isEmpty { try container.encode(address, forKey: .address) }
    }
}
