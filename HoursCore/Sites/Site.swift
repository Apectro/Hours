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

    init(
        id: UUID = UUID(),
        name: String,
        jobID: UUID? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        allowanceByDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.jobID = jobID
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.allowanceByDefault = allowanceByDefault
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, jobID, isArchived, sortOrder, allowanceByDefault
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            name: container.lenient(.name, ""),
            jobID: container.lenientOptional(.jobID),
            isArchived: container.lenient(.isArchived, false),
            sortOrder: container.lenient(.sortOrder, 0),
            allowanceByDefault: container.lenient(.allowanceByDefault, false)
        )
    }

    /// Written by hand so `allowanceByDefault` goes in only when set, and a
    /// site without it is written exactly as before.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(jobID, forKey: .jobID)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(sortOrder, forKey: .sortOrder)
        if allowanceByDefault { try container.encode(allowanceByDefault, forKey: .allowanceByDefault) }
    }
}
