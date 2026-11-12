import Foundation

/// A photo as the outbox needs it: which it is and how big, never its bytes.
struct ConnectPhotoInfo: Hashable, Sendable {
    var id: UUID
    /// The diary's site, the job, the defect or the delivery it belongs to.
    var ownerID: UUID
    var date: CalendarDate?
    var sortOrder: Int
    var byteSize: Int
    /// A defect photo's marks.
    var marks: [DefectMark] = []
    var isAfter = false
}

/// What the phone has on the sites it sends, as the outbox reads it.
struct ConnectOutboxInput: Sendable {
    var sites: [Site]
    var crew: [CrewMember]
    var setups: [UUID: SiteSetup] = [:]
    var siteDays: [SiteDay] = []
    var diaries: [SiteDiary] = []
    var diaryPhotos: [ConnectPhotoInfo] = []
    var signatures: [CrewSignature] = []
    var jobs: [ExtraWorkJob] = []
    var jobPhotos: [ConnectPhotoInfo] = []
    /// The size of each job's client signature drawn as a PNG, by job id;
    /// a job left out is sent without its signature.
    var jobSignatureSizes: [UUID: Int] = [:]
    var defects: [Defect] = []
    var defectPhotos: [ConnectPhotoInfo] = []
    var missing: [MissingItem] = []
    /// Deliveries, and the size of each one's delivery-note photo.
    var deliveries: [Delivery] = []
    var deliveryPhotoSizes: [UUID: Int] = [:]
    /// The name "You" goes by: the name on the sheets, else the device's.
    var yourName: String
    var now: Date
}

/// Sending (phone → web): the app's records on the sites it sends, written
/// as the protocol's, with "You" and every crew row replaced by the
/// company's person (`ConnectPeople`).
///
/// Which sites: those that came from the web, and those made here that the
/// user chose to send (`ConnectState.sharedSites`). A purely private site is
/// never sent.
enum ConnectOutbox {
    /// The kinds a scan covers, for `ConnectState.enqueueScan`. Sheets are
    /// queued by hand, with their PDF, and comments are not written here.
    static let scannedKinds: Set<ConnectV1.RecordKind> = [
        .site, .crewMember, .assignment, .siteDay, .signOff, .extraWork, .defect, .missingItem, .delivery,
    ]

    /// The sites a scan looks at.
    static func scope(_ state: ConnectState, sites: [Site]) -> Set<UUID> {
        Set(sites.map(\.id)).intersection(state.companySites.union(state.sharedSites))
    }

    static func records(_ input: ConnectOutboxInput, state: ConnectState) -> [ConnectOutgoing] {
        let scope = Self.scope(state, sites: input.sites)
        let people = state.people.linking(input.crew)
        var out: [ConnectOutgoing] = []
        func add(_ record: ConnectOutgoing?) { if let record { out.append(record) } }

        let sites = input.sites.filter { scope.contains($0.id) }
        let crew = input.crew.filter { scope.contains($0.siteID) }

        // Sites made here and shared.
        for site in sites where !state.companySites.contains(site.id) {
            add(try? ConnectOutgoing(kind: .site, id: ConnectID.string(site.id), record: siteInput(site, setup: input.setups[site.id] ?? SiteSetup()), siteIDs: [site.id]))
        }

        // People added on the phone, once each, and "You" when the office
        // paired the phone without a person.
        var sentPeople = Set<UUID>()
        for row in crew.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let person = people.rows[row.id], !people.isCompanyPerson(person), person != people.you,
                  sentPeople.insert(person).inserted else { continue }
            let rows = crew.filter { people.rows[$0.id] == person }
            let input = ConnectV1.CrewMemberInput(
                id: ConnectID.string(person),
                name: trimmed(row.name, fallback: "?"),
                hidden: rows.allSatisfy(\.isHidden)
            )
            add(try? ConnectOutgoing(kind: .crewMember, id: ConnectID.string(person), record: input, siteIDs: Array(Set(rows.map(\.siteID))).sorted { $0.uuidString < $1.uuidString }))
        }
        if people.youIsLocal, let you = people.you, !sites.isEmpty {
            let input = ConnectV1.CrewMemberInput(id: ConnectID.string(you), name: trimmed(input.yourName, fallback: "?"), role: .teamLeader)
            add(try? ConnectOutgoing(kind: .crewMember, id: ConnectID.string(you), record: input, siteIDs: sites.map(\.id).sorted { $0.uuidString < $1.uuidString }))
        }

        // Who is on which site, where the web does not already say so.
        let known = Set(state.assignments.values.map { [ConnectID.string($0.siteID), ConnectID.string($0.personID)].joined(separator: ":") })
        var sentAssignments = Set<UUID>()
        func assign(_ person: UUID, to siteID: UUID, role: ConnectV1.CrewRole) {
            let pair = [ConnectID.string(siteID), ConnectID.string(person)].joined(separator: ":")
            guard !known.contains(pair) else { return }
            let id = ConnectUUID.assignmentID(siteID: siteID, personID: person)
            guard sentAssignments.insert(id).inserted else { return }
            let input = ConnectV1.AssignmentInput(id: ConnectID.string(id), siteId: ConnectID.string(siteID), memberId: ConnectID.string(person), role: role)
            add(try? ConnectOutgoing(kind: .assignment, id: ConnectID.string(id), record: input, siteIDs: [siteID]))
        }
        for row in crew where !row.isHidden {
            guard let person = people.rows[row.id], person != people.you else { continue }
            assign(person, to: row.siteID, role: .worker)
        }
        if let you = people.you {
            for site in sites where !state.companySites.contains(site.id) || people.youIsLocal {
                assign(you, to: site.id, role: .teamLeader)
            }
        }

        // Site days, with the diary.
        let diaries = Dictionary(input.diaries.map { ("\($0.siteID.uuidString)|\($0.date.key)", $0) }, uniquingKeysWith: { first, _ in first })
        let diaryPhotos = Dictionary(grouping: input.diaryPhotos) { "\($0.ownerID.uuidString)|\($0.date?.key ?? 0)" }
        for day in input.siteDays where scope.contains(day.siteID) {
            let key = "\(day.siteID.uuidString)|\(day.date.key)"
            let photos = (diaryPhotos[key] ?? []).sorted { $0.sortOrder < $1.sortOrder }.prefix(6)
            let files = photos.map { photo in
                ConnectFileNeed(fileId: ConnectID.string(photo.id), purpose: .photo, contentType: "image/jpeg", byteSize: photo.byteSize, name: nil, source: .diaryPhoto(photo.id))
            }
            let record = siteDay(day, diary: diaries[key], photos: files.map(\.ref), people: people, now: input.now)
            add(try? ConnectOutgoing(kind: .siteDay, id: record.id, record: record, files: files, siteIDs: [day.siteID], month: day.date.yearMonth))
        }

        // Sign-offs.
        for signature in input.signatures where scope.contains(signature.siteID) {
            guard let person = people.outgoing(signature.memberID) else { continue }
            let id = ConnectID.string(ConnectUUID.signOffID(siteID: signature.siteID, memberID: person, month: signature.month))
            let record = ConnectV1.SignOff(
                id: id,
                siteId: ConnectID.string(signature.siteID),
                memberId: ConnectID.string(person),
                month: ConnectFormat.month(signature.month),
                signedOn: ConnectFormat.date(signature.signedOn),
                fingerprint: String(signature.fingerprint.prefix(64)),
                strokes: signature.strokes.prefix(100).map { stroke in
                    stroke.prefix(2000).map { ConnectV1.Point(x: min(max($0.x, 0), 100), y: min(max($0.y, 0), 1)) }
                },
                aspectRatio: min(max(signature.aspectRatio, 0.1), 100)
            )
            add(try? ConnectOutgoing(kind: .signOff, id: id, record: record, siteIDs: [signature.siteID], month: signature.month))
        }

        // Extra work, with its photos and the client's signature.
        let jobPhotos = Dictionary(grouping: input.jobPhotos, by: \.ownerID)
        for job in input.jobs where scope.contains(job.siteID) {
            let photos = (jobPhotos[job.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }.prefix(20).map { photo in
                ConnectFileNeed(fileId: ConnectID.string(photo.id), purpose: .photo, contentType: "image/jpeg", byteSize: photo.byteSize, name: nil, source: .extraWorkPhoto(photo.id))
            }
            var files = Array(photos)
            var signature: ConnectV1.ClientSignature?
            if let drawn = job.clientSignature, let size = input.jobSignatureSizes[job.id], size > 0 {
                let fileID = ConnectUUID.fileID("signature", of: job.id, version: String(Int(drawn.signedAt.timeIntervalSince1970)))
                let need = ConnectFileNeed(fileId: ConnectID.string(fileID), purpose: .signature, contentType: "image/png", byteSize: size, name: nil, source: .extraWorkSignature(job.id))
                files.append(need)
                signature = ConnectV1.ClientSignature(signerName: String(drawn.signerName.prefix(200)), signedAt: ConnectFormat.moment(drawn.signedAt), image: need.ref)
            }
            let record = ConnectV1.ExtraWork(
                id: ConnectID.string(job.id),
                siteId: ConnectID.string(job.siteID),
                date: ConnectFormat.date(job.date),
                description: String(job.description.prefix(4000)),
                materials: job.items.prefix(200).compactMap { item in
                    let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return nil }
                    return ConnectV1.ExtraWorkMaterial(name: String(name.prefix(200)), quantity: ConnectFormat.quantity(item.quantity), unit: item.unit.code)
                },
                hours: job.hours.prefix(50).compactMap { hours in
                    let name = hours.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return nil }
                    return ConnectV1.ExtraWorkHours(
                        memberId: hours.memberID.flatMap(people.outgoing).map(ConnectID.string),
                        name: String(name.prefix(200)),
                        minutes: min(max(hours.minutes, 0), 1440)
                    )
                },
                photos: photos.map(\.ref),
                clientSignature: signature,
                done: job.isDone,
                doneAt: job.isDone ? job.doneAt.map(ConnectFormat.moment) : nil,
                createdAt: ConnectFormat.moment(job.createdAt),
                updatedAt: ConnectFormat.moment(job.updatedAt)
            )
            add(try? ConnectOutgoing(kind: .extraWork, id: record.id, record: record, files: files, siteIDs: [job.siteID], month: job.date.yearMonth))
        }

        // Defects, with their photos and marks.
        let defectPhotos = Dictionary(grouping: input.defectPhotos, by: \.ownerID)
        for defect in input.defects where scope.contains(defect.siteID) {
            let photos = (defectPhotos[defect.id] ?? [])
                .sorted { ($0.isAfter ? 1 : 0, $0.sortOrder) < ($1.isAfter ? 1 : 0, $1.sortOrder) }
                .prefix(20)
            let files = photos.map { photo in
                ConnectFileNeed(fileId: ConnectID.string(photo.id), purpose: .photo, contentType: "image/jpeg", byteSize: photo.byteSize, name: nil, source: .defectPhoto(photo.id))
            }
            let assignee: ConnectV1.DefectAssignee
            switch defect.assignee {
            case .nobody: assignee = ConnectV1.DefectAssignee(kind: "nobody", name: "")
            case .you: assignee = ConnectV1.DefectAssignee(kind: "you", name: "")
            case let .person(name): assignee = ConnectV1.DefectAssignee(kind: "person", name: String(name.prefix(200)))
            }
            let record = ConnectV1.Defect(
                id: ConnectID.string(defect.id),
                siteId: ConnectID.string(defect.siteID),
                what: String(defect.what.prefix(2000)),
                floor: String(defect.floor.prefix(100)),
                room: String(defect.room.prefix(100)),
                assignee: assignee,
                notedBy: String(defect.notedBy.prefix(200)),
                notedAt: ConnectFormat.moment(defect.notedAt),
                state: defect.state.rawValue,
                fixedAt: defect.state == .fixed ? defect.fixedAt.map(ConnectFormat.moment) : nil,
                photos: zip(photos, files).map { photo, file in
                    ConnectV1.DefectPhoto(file: file.ref, marks: photo.marks.prefix(50).map { mark in
                        ConnectV1.DefectMark(kind: mark.kind.rawValue, colour: mark.colour.rawValue, points: mark.points.prefix(2000).map { ConnectV1.Point(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) })
                    })
                },
                updatedAt: ConnectFormat.moment(defect.updatedAt)
            )
            add(try? ConnectOutgoing(kind: .defect, id: record.id, record: record, files: Array(files), siteIDs: [defect.siteID]))
        }

        // Missing, and deliveries.
        for item in input.missing where scope.contains(item.siteID) {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let record = ConnectV1.MissingItem(
                id: ConnectID.string(item.id),
                siteId: ConnectID.string(item.siteID),
                name: String(name.prefix(200)),
                quantity: ConnectFormat.quantity(item.quantity),
                unit: item.unit.code,
                note: String(item.note.prefix(1000)),
                notedBy: String(item.notedBy.prefix(200)),
                notedAt: ConnectFormat.moment(item.notedAt),
                state: item.state.rawValue,
                orderedAt: item.orderedAt.map(ConnectFormat.moment),
                arrivedAt: item.arrivedAt.map(ConnectFormat.moment),
                updatedAt: ConnectFormat.moment(item.updatedAt)
            )
            add(try? ConnectOutgoing(kind: .missingItem, id: record.id, record: record, siteIDs: [item.siteID]))
        }
        for delivery in input.deliveries where scope.contains(delivery.siteID) {
            var files: [ConnectFileNeed] = []
            if delivery.hasPhoto, let size = input.deliveryPhotoSizes[delivery.id], size > 0 {
                let fileID = ConnectUUID.fileID("deliveryPhoto", of: delivery.id)
                files.append(ConnectFileNeed(fileId: ConnectID.string(fileID), purpose: .deliveryPhoto, contentType: "image/jpeg", byteSize: size, name: nil, source: .deliveryPhoto(delivery.id)))
            }
            let record = ConnectV1.Delivery(
                id: ConnectID.string(delivery.id),
                siteId: ConnectID.string(delivery.siteID),
                receivedAt: ConnectFormat.moment(delivery.receivedAt),
                lines: delivery.lines.prefix(200).compactMap { line in
                    let name = line.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return nil }
                    return ConnectV1.DeliveryLine(
                        kind: line.kind.rawValue,
                        name: String(name.prefix(200)),
                        unit: line.unit.code,
                        came: ConnectFormat.quantity(line.came),
                        ordered: ConnectFormat.quantity(line.ordered),
                        missingItemId: line.missingItemID.map(ConnectID.string)
                    )
                },
                photo: files.first?.ref,
                updatedAt: ConnectFormat.moment(delivery.updatedAt)
            )
            add(try? ConnectOutgoing(kind: .delivery, id: record.id, record: record, files: files, siteIDs: [delivery.siteID]))
        }
        return out
    }

    // MARK: - One record

    static func siteInput(_ site: Site, setup: SiteSetup) -> ConnectV1.SiteInput {
        var usual: ConnectV1.UsualDay?
        if let start = setup.start, let end = setup.end {
            usual = ConnectV1.UsualDay(start: ConnectFormat.time(start), end: ConnectFormat.time(end), breakMinutes: min(max(setup.breakMinutes, 0), 1440))
        }
        return ConnectV1.SiteInput(
            id: ConnectID.string(site.id),
            name: trimmed(site.name, fallback: "?"),
            address: String(site.address.prefix(500)),
            workDays: setup.workDays.sorted(),
            usualDay: usual,
            pause: setup.pause.map { ConnectV1.SitePause(start: ConnectFormat.date($0.start), end: $0.end.map(ConnectFormat.date)) },
            archived: site.isArchived,
            allowanceByDefault: site.allowanceByDefault
        )
    }

    /// A site day as the protocol's, with the company's people in it. A row
    /// with no person yet is left out (`ConnectPeople.linking` gives every
    /// row one before this runs).
    static func siteDay(_ day: SiteDay, diary: SiteDiary?, photos: [ConnectV1.FileRef], people: ConnectPeople, now: Date) -> ConnectV1.SiteDay {
        func id(_ member: UUID) -> String? { people.outgoing(member).map(ConnectID.string) }
        func time(_ value: TimeOfDay?) -> String? { value.map(ConnectFormat.time) }
        var seen = Set<String>()
        let attendance = day.present.compactMap { entry -> ConnectV1.Attendance? in
            guard let member = id(entry.memberID), seen.insert(member).inserted else { return nil }
            return ConnectV1.Attendance(memberId: member, start: time(entry.start), end: time(entry.end), breakMinutes: entry.breakMinutes.map { min(max($0, 0), 1440) })
        }
        let absences = day.absences.compactMap { absence -> ConnectV1.Absence? in
            guard let member = id(absence.memberID), !seen.contains(member) else { return nil }
            switch absence.reason {
            case let .dayType(type):
                return ConnectV1.Absence(memberId: member, reason: ConnectV1.AbsenceReason(type: "dayType", dayType: type.rawValue, siteId: nil))
            case let .otherSite(site):
                return ConnectV1.Absence(memberId: member, reason: ConnectV1.AbsenceReason(type: "otherSite", dayType: nil, siteId: site.map(ConnectID.string)))
            }
        }
        let present = Set(attendance.map(\.memberId))
        let allowance = day.allowanceMemberIDs.compactMap(id).filter(present.contains)
        let moves = day.moves.compactMap { move -> ConnectV1.SiteMove? in
            let members = move.memberIDs.compactMap(id)
            guard !members.isEmpty else { return nil }
            return ConnectV1.SiteMove(
                id: ConnectID.string(move.id),
                toSiteId: ConnectID.string(move.toSiteID),
                left: ConnectFormat.time(move.left),
                started: ConnectFormat.time(move.started),
                breakPlacement: move.breakPlacement.rawValue,
                memberIds: members
            )
        }
        var wireDiary: ConnectV1.SiteDiary?
        if let diary, !(diary.isBlank && photos.isEmpty) {
            wireDiary = ConnectV1.SiteDiary(
                weather: diary.weather?.rawValue,
                temperatureCelsius: diary.temperatureCelsius.map { min(max($0, -60), 60) },
                workDone: String(diary.workDone.prefix(4000)),
                deliveries: String(diary.deliveries.prefix(4000)),
                problems: String(diary.problems.prefix(4000)),
                visitors: String(diary.visitors.prefix(4000)),
                photos: Array(photos.prefix(6))
            )
        }
        return ConnectV1.SiteDay(
            id: ConnectID.string(ConnectUUID.siteDayID(siteID: day.siteID, date: day.date)),
            siteId: ConnectID.string(day.siteID),
            date: ConnectFormat.date(day.date),
            start: time(day.start),
            end: time(day.end),
            breakMinutes: min(max(day.breakMinutes, 0), 1440),
            attendance: attendance,
            absences: absences,
            noWork: day.noWork?.rawValue,
            badWeatherStop: day.isBadWeatherStop,
            note: String(day.note.prefix(4000)),
            allowanceMemberIds: Array(Set(allowance)).sorted(),
            kilometres: min(max(day.kilometres, 0), 100_000),
            moves: moves,
            diary: wireDiary,
            writtenBy: people.you.map(ConnectID.string),
            updatedAt: ConnectFormat.moment(now)
        )
    }

    private static func trimmed(_ text: String, fallback: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((value.isEmpty ? fallback : value).prefix(200))
    }
}
