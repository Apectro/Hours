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

    init(
        id: UUID = UUID(),
        name: String,
        jobID: UUID? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.jobID = jobID
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, jobID, isArchived, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            name: container.lenient(.name, ""),
            jobID: container.lenientOptional(.jobID),
            isArchived: container.lenient(.isArchived, false),
            sortOrder: container.lenient(.sortOrder, 0)
        )
    }
}
