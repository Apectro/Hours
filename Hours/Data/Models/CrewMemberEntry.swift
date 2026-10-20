import Foundation
import SwiftData

/// A stored crew member. Mirrors `CrewMember`, decomposed into primitives.
///
/// Belongs to its site through `siteID` rather than a relationship: a
/// relationship would tie the two rows' sync together for no gain, and the
/// repository looks members up by site either way. "You" is never stored
/// here; see `CrewMember.youID`.
@Model
final class CrewMemberEntry {
    /// `CrewMember.id`, as `uuidString`. Unique by rule, like `SiteEntry.siteID`.
    var memberID: String = ""
    /// `CrewMember.siteID`, as `uuidString`.
    var siteID: String = ""
    var name: String = ""
    var isHidden: Bool = false
    var sortOrder: Int = 0
    var updatedAt: Date = Date()

    init(member: CrewMember) {
        self.memberID = member.id.uuidString
        self.siteID = member.siteID.uuidString
        self.updatedAt = Date()
        apply(member)
    }
}

extension CrewMemberEntry {
    /// The value-type view of this entry. A damaged identifier falls back to
    /// a fresh one, as `CrewMember`'s lenient decoding does.
    var member: CrewMember {
        CrewMember(
            id: UUID(uuidString: memberID) ?? UUID(),
            siteID: UUID(uuidString: siteID) ?? UUID(),
            name: name,
            isHidden: isHidden,
            sortOrder: sortOrder
        )
    }

    /// Copies a member onto this entry. Neither `memberID` nor `siteID`
    /// changes: a member does not move between sites, and attendances on past
    /// days point at this identity.
    func apply(_ member: CrewMember) {
        name = member.name
        isHidden = member.isHidden
        sortOrder = member.sortOrder
        updatedAt = Date()
    }
}
