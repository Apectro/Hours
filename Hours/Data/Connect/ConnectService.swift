import Foundation
import Network
import Observation
import SwiftData
import UIKit

/// A month sheet to send to the company: which sites, which month, and the
/// title printed on it. Made by the export screen.
struct ConnectSheetOrder: Hashable, Sendable {
    var siteIDs: [UUID]
    var month: YearMonth
    var title: String
}

/// "Connect to company" (free, off until paired): the app's side of the
/// company's own website. Carries out what the engine decides —
/// `ConnectSession` for pairing, receiving and sending, `ConnectMerge` for
/// what a sync changes, `ConnectOutbox` and `ConnectSheet` for what goes —
/// and reads and writes the store, the settings and the files it needs.
///
/// When it talks to the site: right after pairing; when the app comes to the
/// foreground; a few seconds after a save (debounced); when the network
/// comes back; after a failure, when the backoff allows; and on Sync now.
/// The app has no background refresh task, so none is added for this.
///
/// Nothing leaves the phone while it is not connected.
@MainActor
@Observable
final class ConnectService {
    /// UI tests: talk to an in-memory company (`ConnectStubTransport`)
    /// instead of the network, and send only on Sync now.
    static let stubLaunchArgument = "-hours-connect-stub"

    private(set) var account: ConnectAccount?
    private(set) var state: ConnectState
    private(set) var isWorking = false
    /// What went wrong last, for the Connect screen; nil once things work.
    private(set) var problem: ConnectError?
    /// The office revoked this phone: said once on the Connect screen.
    private(set) var wasDisconnectedByOffice = false
    private(set) var hasToken: Bool

    private let storage: ConnectStorage
    private let transport: ConnectTransport
    private let sendsByItself: Bool
    private let container: () -> ModelContainer
    private let settingsStore: () -> SettingsStore
    @ObservationIgnored private var saveObserver: NSObjectProtocol?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var photoSizes: [UUID: Int] = [:]
    @ObservationIgnored private var started = false
    @ObservationIgnored private var isMerging = false

    init(
        storage: ConnectStorage,
        transport: ConnectTransport,
        sendsByItself: Bool,
        container: @escaping () -> ModelContainer,
        settingsStore: @escaping () -> SettingsStore
    ) {
        self.storage = storage
        self.transport = transport
        self.sendsByItself = sendsByItself
        self.container = container
        self.settingsStore = settingsStore
        self.account = storage.account
        self.state = storage.state
        self.hasToken = storage.token != nil
    }

    var isConnected: Bool { account != nil && hasToken }
    var waitingCount: Int { state.queue.count }
    var companyName: String? { isConnected ? account?.companyName : nil }

    private var context: ModelContext { container().mainContext }
    private var settings: AppSettings { settingsStore().settings }
    private var calendar: Calendar { settingsStore().workCalendar }

    private func client() -> ConnectClient? {
        guard let account, let url = account.url, let token = storage.token else { return nil }
        return ConnectClient(baseURL: url, transport: transport, token: token)
    }

    // MARK: - Starting

    /// Once, when the app's window is up: watches saves and the network,
    /// and syncs if connected.
    func start() {
        guard !started else { return }
        started = true
        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteChange() }
        }
        if sendsByItself {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor in self?.networkCameBack() }
            }
            monitor.start(queue: DispatchQueue(label: "app.zeitkonto.connect.path"))
            pathMonitor = monitor
        }
        foreground()
    }

    /// The app came to the foreground: sync, then send.
    func foreground() {
        guard isConnected, sendsByItself else { return }
        Task { await syncNow() }
    }

    private func networkCameBack() {
        guard isConnected, sendsByItself, !state.queue.isEmpty, !isWorking else { return }
        Task { await send() }
    }

    /// Something was saved: look for changed records a few seconds later,
    /// so a burst of saves is one look.
    private func noteChange() {
        guard isConnected, !isMerging else { return }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.scan()
            if self.sendsByItself { await self.send() }
        }
    }

    // MARK: - Pairing

    /// Pairs with the site at `address` by `code`, then takes in the first
    /// full sync. True when connected.
    @discardableResult
    func pair(address: URL, code: String) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        let pairing = ConnectClient(baseURL: address, transport: transport)
        do {
            let paired = try await ConnectSession.pair(client: pairing, code: code, device: deviceInfo(), now: Date())
            storage.token = paired.token
            hasToken = true
            account = paired.account
            storage.account = paired.account
            state = paired.state
            persist()
            problem = nil
            wasDisconnectedByOffice = false
        } catch {
            problem = (error as? ConnectError) ?? .offline
            return false
        }
        do {
            try await receive()
            scan()
            if sendsByItself { await sendQueue() }
        } catch {
            handle(error)
        }
        return true
    }

    /// Disconnect: tells the site (`POST /v1/device/unpair`), then forgets
    /// the token, the cursor and the queue. The data on the phone stays.
    func disconnect() async {
        if let client = client() {
            _ = try? await client.unpair()
        }
        forget(byOffice: false)
    }

    private func forget(byOffice: Bool) {
        scanTask?.cancel()
        retryTask?.cancel()
        storage.token = nil
        hasToken = false
        storage.account = nil
        account = nil
        state = ConnectState.disconnected
        persist()
        problem = nil
        wasDisconnectedByOffice = byOffice
        try? FileManager.default.contentsOfDirectory(at: storage.filesFolder, includingPropertiesForKeys: nil)
            .forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func deviceInfo() -> ConnectV1.DeviceInfo {
        let bundle = Bundle.main
        return ConnectV1.DeviceInfo(
            name: String(UIDevice.current.name.prefix(120)),
            model: Self.hardwareModel,
            platform: UIDevice.current.userInterfaceIdiom == .pad ? "ipados" : "ios",
            osVersion: UIDevice.current.systemVersion,
            appVersion: (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    private static var hardwareModel: String? {
        var info = utsname()
        uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return model.isEmpty ? nil : String(model.prefix(80))
    }

    // MARK: - Sync now

    /// Receives, looks for changes, and sends: Sync now, and the foreground.
    func syncNow() async {
        guard isConnected, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await receive()
            problem = nil
        } catch {
            handle(error)
            if !isConnected { return }
        }
        scan()
        await sendQueue()
    }

    /// Sends what is waiting, when nothing else is talking to the site.
    func send() async {
        guard isConnected, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await sendQueue()
    }

    private func handle(_ error: Error) {
        let error = (error as? ConnectError) ?? .offline
        if error.disconnects {
            forget(byOffice: true)
            return
        }
        problem = error
    }

    // MARK: - Receiving

    private func receive() async throws {
        guard let client = client() else { return }
        let lock = settings.monthLock
        let today = CalendarDate.today(in: calendar)
        state = try await ConnectSession.receive(
            client: client,
            state: state,
            lock: lock,
            today: today,
            now: Date(),
            local: { [unowned self] in self.localForMerge() },
            apply: { [unowned self] plan in self.apply(plan) }
        )
        persist()
    }

    private static let allTime = CalendarDateRange(
        start: CalendarDate(year: 2000, month: 1, day: 1),
        end: CalendarDate(year: 2100, month: 12, day: 31)
    )

    private func localForMerge() -> ConnectLocal {
        let repository = SiteRepository(context: context)
        let sites = repository.sites(includeArchived: true)
        let crew = sites.flatMap { repository.crew(for: $0.id, includeHidden: true) }
        var dates: [UUID: Set<CalendarDate>] = [:]
        for day in repository.siteDays(siteID: nil, in: Self.allTime) {
            dates[day.siteID, default: []].insert(day.date)
        }
        var setups: [UUID: SiteSetup] = [:]
        for site in sites { setups[site.id] = settings.siteSetup(for: site.id) }
        return ConnectLocal(sites: sites, crew: crew, setups: setups, writtenDates: dates)
    }

    /// Writes what a sync page changes. Sites and crew rows are not dated,
    /// so the month lock is not theirs to ask; no day is ever written here.
    private func apply(_ plan: ConnectMergePlan) {
        isMerging = true
        defer { isMerging = false }
        let repository = SiteRepository(context: context)
        for site in plan.sites { repository.upsert(site) }
        for member in plan.crew { repository.upsert(member) }
        if !plan.setups.isEmpty {
            settingsStore().update { settings in
                for (id, setup) in plan.setups { settings.setSiteSetup(setup, for: id) }
            }
        }
        state = plan.state
        persist()
    }

    // MARK: - Sending

    /// Looks through the sites the company sees for records that changed
    /// since they were last queued, and queues them.
    func scan() {
        guard isConnected else { return }
        let input = outboxInput()
        let records = ConnectOutbox.records(input, state: state)
        let scope = ConnectOutbox.scope(state, sites: input.sites)
        state.people = state.people.linking(input.crew)
        state.enqueueScan(records, kinds: ConnectOutbox.scannedKinds, sites: scope, at: Date())
        persist()
    }

    private func sendQueue() async {
        guard let client = client(), !state.queue.isEmpty else { return }
        var working = state
        let report = await ConnectSession.send(
            client: client,
            state: &working,
            now: { Date() },
            jitter: { Double.random(in: 0...1) },
            fileBytes: { [unowned self] file in self.bytes(of: file) }
        )
        state = working
        persist()
        if let error = report.stoppedBy {
            handle(error)
            scheduleRetry()
        } else if !report.deferred {
            problem = nil
        } else {
            scheduleRetry()
        }
    }

    /// Tries again once the backoff allows, while the app is open.
    private func scheduleRetry() {
        guard sendsByItself, isConnected, let notBefore = state.backoff.notBefore else { return }
        retryTask?.cancel()
        let wait = max(1, notBefore.timeIntervalSinceNow)
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.send()
        }
    }

    private func outboxInput() -> ConnectOutboxInput {
        let repository = SiteRepository(context: context)
        let allSites = repository.sites(includeArchived: true)
        let scope = ConnectOutbox.scope(state, sites: allSites)
        let sites = allSites.filter { scope.contains($0.id) }
        let diaryRepository = SiteDiaryRepository(context: context)
        let extraWork = ExtraWorkRepository(context: context)
        let defectRepository = DefectRepository(context: context)
        let missing = MissingRepository(context: context)
        let deliveryRepository = DeliveryRepository(context: context)

        var input = ConnectOutboxInput(sites: sites, crew: [], yourName: yourName, now: Date())
        for site in sites {
            input.setups[site.id] = settings.siteSetup(for: site.id)
            input.crew += repository.crew(for: site.id, includeHidden: true)
            let days = repository.siteDays(siteID: site.id, in: Self.allTime)
            input.siteDays += days
            input.diaries += diaryRepository.diaries(siteID: site.id, in: Self.allTime)

            let references = diaryRepository.photoReferences(siteID: site.id, in: Self.allTime)
            let unknown = Set(references.map(\.id)).subtracting(photoSizes.keys)
            if !unknown.isEmpty {
                for (id, data) in diaryRepository.photoData(ids: unknown, siteID: site.id, in: Self.allTime) {
                    photoSizes[id] = data.count
                }
            }
            input.diaryPhotos += references.compactMap { reference in
                photoSizes[reference.id].map { ConnectPhotoInfo(id: reference.id, ownerID: site.id, date: reference.date, sortOrder: reference.sortOrder, byteSize: $0) }
            }

            for month in Set(days.map(\.date.yearMonth)) {
                input.signatures += diaryRepository.signatures(siteID: site.id, month: month)
            }

            for job in extraWork.jobs(siteID: site.id) {
                input.jobs.append(job)
                for photo in extraWork.photos(jobID: job.id) {
                    input.jobPhotos.append(ConnectPhotoInfo(id: photo.id, ownerID: job.id, sortOrder: photo.sortOrder, byteSize: photo.jpegData.count))
                }
                if let signature = job.clientSignature, let png = Self.png(signature) {
                    input.jobSignatureSizes[job.id] = png.count
                }
            }

            for defect in defectRepository.defects(siteID: site.id) {
                input.defects.append(defect)
                for photo in defectRepository.photos(defectID: defect.id) {
                    input.defectPhotos.append(ConnectPhotoInfo(
                        id: photo.id, ownerID: defect.id, sortOrder: photo.sortOrder,
                        byteSize: photo.jpegData.count, marks: photo.marks, isAfter: photo.isAfter
                    ))
                }
            }

            input.missing += missing.items(siteID: site.id)
            for delivery in deliveryRepository.deliveries(siteID: site.id) {
                input.deliveries.append(delivery)
                guard delivery.hasPhoto else { continue }
                if photoSizes[delivery.id] == nil {
                    photoSizes[delivery.id] = deliveryRepository.delivery(id: delivery.id)?.photoData?.count
                }
                input.deliveryPhotoSizes[delivery.id] = photoSizes[delivery.id]
            }
        }
        return input
    }

    /// The name "You" goes by on the sheets.
    private var yourName: String {
        let owner = settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty { return owner }
        return account?.memberName ?? UIDevice.current.name
    }

    /// The bytes of a file a record refers to, read when it is uploaded.
    private func bytes(of file: ConnectFileNeed) -> Data? {
        switch file.source {
        case let .diaryPhoto(id):
            let key = id.uuidString
            return fetchFirst(FetchDescriptor<SiteDiaryPhotoEntry>(predicate: #Predicate<SiteDiaryPhotoEntry> { $0.photoID == key }))?.jpegData
        case let .extraWorkPhoto(id):
            let key = id.uuidString
            return fetchFirst(FetchDescriptor<ExtraWorkPhotoEntry>(predicate: #Predicate<ExtraWorkPhotoEntry> { $0.photoID == key }))?.jpegData
        case let .defectPhoto(id):
            let key = id.uuidString
            return fetchFirst(FetchDescriptor<DefectPhotoEntry>(predicate: #Predicate<DefectPhotoEntry> { $0.photoID == key }))?.jpegData
        case let .deliveryPhoto(id):
            return DeliveryRepository(context: context).delivery(id: id)?.photoData
        case let .extraWorkSignature(id):
            return ExtraWorkRepository(context: context).job(id: id)?.clientSignature.flatMap(Self.png)
        case let .stored(name):
            return try? Data(contentsOf: storage.filesFolder.appendingPathComponent(name))
        }
    }

    private func fetchFirst<Entity: PersistentModel>(_ descriptor: FetchDescriptor<Entity>) -> Entity? {
        var descriptor = descriptor
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// The client's signature as a PNG: black ink on white, as printed.
    nonisolated private static func png(_ signature: ExtraWorkSignature) -> Data? {
        guard !signature.strokes.isEmpty else { return nil }
        let height: CGFloat = 200
        let size = CGSize(width: height * CGFloat(max(signature.aspectRatio, 0.1)), height: height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            PDFAppendix.drawStrokes(signature.strokes, aspectRatio: signature.aspectRatio, in: CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8))
        }
        return image.pngData()
    }

    // MARK: - Month sheets

    /// Whether every site of a sheet is one the company sees.
    func canSend(siteIDs: [UUID]) -> Bool {
        guard isConnected, !siteIDs.isEmpty else { return false }
        let known = state.companySites.union(state.sharedSites)
        return siteIDs.allSatisfy(known.contains)
    }

    /// Queues a month sheet with its PDF (and an Excel or CSV beside it)
    /// and sends it. Sent again after a return, it is the corrected version.
    @discardableResult
    func sendSheet(_ order: ConnectSheetOrder, pdf: Data?, attachments: [URL] = []) async -> Bool {
        guard canSend(siteIDs: order.siteIDs) else { return false }
        let repository = SiteRepository(context: context)
        let range = order.month.range(in: calendar)
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let inputs = order.siteIDs.compactMap { id -> ConnectSheet.SiteInput? in
            guard let site = repository.site(id: id) else { return nil }
            return ConnectSheet.SiteInput(
                site: site,
                crew: repository.crew(for: id, includeHidden: true),
                results: repository.siteDays(siteID: id, in: range).map(calculator.compute)
            )
        }
        guard !inputs.isEmpty else { return false }
        let rules = WorkdayRepository(context: context).holidayRules()
        let holidays = HolidayResolver(rules: rules, calendar: calendar, covering: range)
            .daysOff(in: range, calendar: calendar)
            .map { (date: $0.key, name: $0.value) }

        let sheetID = ConnectSheet.id(siteIDs: order.siteIDs, month: order.month)
        var files: [ConnectFileNeed] = []
        var pdfRef: ConnectV1.FileRef?
        if let pdf, !pdf.isEmpty, let need = store(pdf, purpose: .sheetPdf, contentType: "application/pdf", extension: "pdf", sheetID: sheetID, name: order.title) {
            files.append(need)
            pdfRef = need.ref
        }
        var attachmentRefs: [ConnectV1.FileRef] = []
        for url in attachments {
            guard let data = try? Data(contentsOf: url) else { continue }
            let isCSV = url.pathExtension.lowercased() == "csv"
            let need = store(
                data,
                purpose: isCSV ? .sheetCsv : .sheetXlsx,
                contentType: isCSV ? "text/csv" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                extension: isCSV ? "csv" : "xlsx",
                sheetID: sheetID,
                name: url.lastPathComponent
            )
            if let need {
                files.append(need)
                attachmentRefs.append(need.ref)
            }
        }

        let sheet = ConnectSheet.make(
            sites: inputs,
            month: order.month,
            title: order.title,
            holidays: holidays,
            breaksPaid: settings.primaryJob.breaksArePaid,
            rounding: settings.rounding,
            people: state.people.linking(inputs.flatMap(\.crew)),
            yourName: yourName,
            pdf: pdfRef,
            attachments: attachmentRefs,
            sentAt: Date()
        )
        guard var record = try? ConnectSheet.outgoing(sheet, pdfFile: nil, siteIDs: order.siteIDs) else { return false }
        record.files = files
        state.enqueue([record], at: Date(), force: true)
        persist()
        await send()
        return true
    }

    /// Writes a sheet's file into the Connect folder, where it waits until
    /// it is uploaded; its id follows its bytes, so a new PDF is a new file.
    private func store(_ data: Data, purpose: ConnectV1.FilePurpose, contentType: String, extension ext: String, sheetID: UUID, name: String) -> ConnectFileNeed? {
        let fileID = ConnectUUID.fileID(purpose.rawValue, of: sheetID, version: String(ConnectUUID.digest(data).prefix(16)))
        let fileName = ConnectID.string(fileID) + "." + ext
        do {
            try data.write(to: storage.filesFolder.appendingPathComponent(fileName), options: .atomic)
        } catch {
            return nil
        }
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ConnectFileNeed(
            fileId: ConnectID.string(fileID),
            purpose: purpose,
            contentType: contentType,
            byteSize: data.count,
            name: base.isEmpty ? nil : String(base.prefix(190)) + (base.lowercased().hasSuffix("." + ext) ? "" : "." + ext),
            source: .stored(fileName)
        )
    }

    // MARK: - Sites the phone made

    /// Whether a site made on this phone is sent to the company.
    func isShared(_ siteID: UUID) -> Bool { state.sharedSites.contains(siteID) }

    func setShared(_ shared: Bool, siteID: UUID) {
        guard isConnected, !state.companySites.contains(siteID) else { return }
        if shared { state.sharedSites.insert(siteID) } else { state.sharedSites.remove(siteID) }
        persist()
        scan()
        if sendsByItself { Task { await send() } }
    }

    // MARK: - What the screens show

    /// The company's name, for a site that came from it.
    func companyName(forSite siteID: UUID) -> String? {
        guard isConnected, state.companySites.contains(siteID) else { return nil }
        return account?.companyName
    }

    /// What the office returned on a site, newest first.
    func returns(onSite siteID: UUID) -> [ConnectReturn] {
        guard isConnected else { return [] }
        return state.returns(onSite: siteID)
    }

    /// The office's notes on a site, newest first.
    func notes(onSite siteID: UUID) -> [ConnectV1.Comment] {
        guard isConnected else { return [] }
        return state.comments(on: .site, id: ConnectID.string(siteID)).filter { $0.purpose != "return" }.reversed()
    }

    /// The state line of a site day.
    func status(ofDayOn siteID: UUID, date: CalendarDate) -> ConnectRecordStatus? {
        guard isConnected, state.companySites.union(state.sharedSites).contains(siteID) else { return nil }
        return state.status(of: .siteDay, id: ConnectID.string(ConnectUUID.siteDayID(siteID: siteID, date: date)))
    }

    /// The state line of a month sheet.
    func status(ofSheet siteIDs: [UUID], month: YearMonth) -> ConnectRecordStatus? {
        guard canSend(siteIDs: siteIDs) else { return nil }
        return state.status(of: .sheet, id: ConnectID.string(ConnectSheet.id(siteIDs: siteIDs, month: month)))
    }

    /// Sites made on this phone, which may be sent if chosen.
    func ownSites() -> [Site] {
        guard isConnected else { return [] }
        return SiteRepository(context: context).sites(includeArchived: false).filter { !state.companySites.contains($0.id) }
    }

    private func persist() {
        storage.state = state
    }
}
