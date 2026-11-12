import SwiftUI

/// Settings › Connect to company (free, off until paired): scan the QR code
/// on the company's website or type its address and code, then see who the
/// phone is connected as, when it last synced, what is waiting, Sync now
/// and Disconnect. The footer says what is sent and to whom.
struct ConnectScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    @State private var address = ""
    @State private var code = ""
    @State private var scanning = false
    @State private var confirming: ConnectPairingRequest?
    @State private var confirmsDisconnect = false
    @State private var entryProblem: String?

    private var connect: ConnectService { HoursStack.connect }

    var body: some View {
        List {
            if connect.isConnected {
                connectedSections
            } else {
                pairingSections
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Connect to company")
        .navigationBarTitleDisplayMode(.inline)
        // A screen the UI tests wait for, on the list.
        .accessibilityIdentifier("screen-connect")
        .sheet(isPresented: $scanning) {
            ConnectScanSheet { text in
                scanning = false
                read(scanned: text)
            }
        }
        .alert(
            confirmTitle,
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { request in
            Button("Connect") {
                confirming = nil
                Task { await pair(request) }
            }
            .accessibilityIdentifier("connect-confirm")
            Button("Cancel", role: .cancel) { confirming = nil }
        } message: { _ in
            Text("Site days, month sheets, sign-offs, extra work, defects, Missing and deliveries of the company's sites will be sent to this website.")
        }
        .alert(disconnectTitle, isPresented: $confirmsDisconnect) {
            Button("Disconnect", role: .destructive) {
                Task { await connect.disconnect() }
            }
            .accessibilityIdentifier("connect-disconnect-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This phone stops sending. Everything on it stays.")
        }
        .task {
            if connect.isConnected { connect.scan() }
        }
    }

    // MARK: - Not connected

    @ViewBuilder
    private var pairingSections: some View {
        if connect.wasDisconnectedByOffice {
            Section {
                Label {
                    Text("This phone was disconnected by the office.")
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.hoursAttention)
                }
                .accessibilityIdentifier("connect-revoked")
            }
        }

        Section {
            Button {
                entryProblem = nil
                scanning = true
            } label: {
                Label("Scan the QR code", systemImage: "qrcode.viewfinder")
            }
            .accessibilityIdentifier("connect-scan")
        } footer: {
            Text("On your company's website, the office opens Connect a phone and shows a QR code.")
        }

        Section {
            TextField("Website address", text: $address)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("connect-address")
            TextField("Code", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .monospaced()
                .accessibilityIdentifier("connect-code")
            Button {
                typedConnect()
            } label: {
                HStack {
                    Text("Connect")
                    if connect.isWorking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(connect.isWorking || address.trimmingCharacters(in: .whitespaces).isEmpty || code.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("connect-pair")
        } header: {
            Text("Or type them")
        } footer: {
            if let message = entryProblem ?? connect.problem.map(ConnectText.problem) {
                Text(verbatim: message)
                    .foregroundStyle(Color.hoursMissing)
                    .accessibilityIdentifier("connect-problem")
            } else {
                Text("The address and the eight-character code are under the QR code.")
            }
        }

        Section {
            EmptyView()
        } footer: {
            Text("Free. Nothing leaves your phone unless you connect it. Once connected, the site days, month sheets, sign-offs, extra work, defects, Missing and deliveries of your company's sites go to your company's own website, and nowhere else.")
        }
    }

    private func typedConnect() {
        guard let url = ConnectPairing.address(address) else {
            entryProblem = ConnectText.problem(.badAddress)
            return
        }
        guard let normalized = ConnectPairing.normalizedCode(code) else {
            entryProblem = ConnectText.problem(.pairingCodeInvalid)
            return
        }
        entryProblem = nil
        confirming = ConnectPairingRequest(url: url, code: normalized)
    }

    private func read(scanned text: String) {
        do {
            let read = try ConnectPairing.parseQR(text)
            address = read.url.absoluteString
            code = read.code
            entryProblem = nil
            confirming = ConnectPairingRequest(url: read.url, code: read.code)
        } catch {
            entryProblem = ConnectText.problem((error as? ConnectError) ?? .badAddress)
        }
    }

    private func pair(_ request: ConnectPairingRequest) async {
        if await connect.pair(address: request.url, code: request.code) {
            address = ""
            code = ""
        }
    }

    private var confirmTitle: String {
        let host = confirming.map { ConnectPairing.host(of: $0.url) } ?? ""
        return String(localized: "Connect to \(host)?", comment: "Connect to company: asked before pairing; the value is the company's website, such as firm.example")
    }

    // MARK: - Connected

    @ViewBuilder
    private var connectedSections: some View {
        if let problem = connect.problem {
            Section {
                Label {
                    Text(verbatim: ConnectText.problem(problem))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.hoursAttention)
                }
                .font(.subheadline)
                .accessibilityIdentifier("connect-problem")
            }
        }

        Section {
            LabeledContent {
                Text(verbatim: connect.account?.companyName ?? "")
            } label: {
                Text("Company")
            }
            .accessibilityIdentifier("connect-company")

            Label {
                Text(verbatim: connectedAs)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.hoursDone)
            }
            .accessibilityIdentifier("connect-state-connected")

            LabeledContent {
                Text(verbatim: lastSynced)
                    .monospacedDigit()
            } label: {
                Text("Last synced")
            }
            .accessibilityIdentifier("connect-last-synced")

            if connect.waitingCount > 0 {
                LabeledContent {
                    Text(verbatim: String(
                        localized: "\(connect.waitingCount) waiting",
                        comment: "Connect to company: how many records are waiting to be sent; the value is a number"
                    ))
                    .monospacedDigit()
                } label: {
                    Text("To send")
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(Text(verbatim: String(connect.waitingCount)))
                .accessibilityIdentifier("connect-waiting")
            } else {
                LabeledContent {
                    Text("Up to date")
                } label: {
                    Text("To send")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("connect-up-to-date")
            }
        } footer: {
            Text(verbatim: ConnectPairing.host(of: connect.account?.url ?? URL(fileURLWithPath: "/")))
        }

        Section {
            Button {
                Task { await connect.syncNow() }
            } label: {
                HStack {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    if connect.isWorking {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(connect.isWorking)
            .accessibilityIdentifier("connect-sync-now")
        }

        officeSection

        let own = connect.ownSites()
        if !own.isEmpty {
            Section {
                ForEach(Array(own.enumerated()), id: \.element.id) { index, site in
                    Toggle(isOn: Binding(
                        get: { connect.isShared(site.id) },
                        set: { connect.setShared($0, siteID: site.id) }
                    )) {
                        Text(verbatim: site.name)
                    }
                    .accessibilityIdentifier("connect-share-\(index)")
                }
            } header: {
                Text("Your own sites")
            } footer: {
                Text("A site made on this phone goes to the company only when switched on here.")
            }
        }

        Section {
            Button(role: .destructive) {
                confirmsDisconnect = true
            } label: {
                Text("Disconnect")
            }
            .accessibilityIdentifier("connect-disconnect")
        } footer: {
            Text(verbatim: sentFooter)
        }
    }

    /// What the office sent back, and what a closed month stopped.
    @ViewBuilder
    private var officeSection: some View {
        let returns = connect.state.returns(onSite: nil)
        let locked = connect.state.lockedConflicts.suffix(5)
        if !returns.isEmpty || !locked.isEmpty {
            Section {
                ForEach(returns, id: \.self) { item in
                    Label {
                        Text(verbatim: ConnectText.returned(item.comment))
                    } icon: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(Color.hoursAttention)
                    }
                    .font(.subheadline)
                }
                ForEach(Array(locked), id: \.self) { conflict in
                    Label {
                        Text(verbatim: ConnectText.closedMonth(conflict, formatting: settingsStore.dateFormatting))
                    } icon: {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.hoursSecondaryText)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("From the office")
            }
        }
    }

    private var connectedAs: String {
        let name = connect.account?.memberName ?? settingsStore.settings.export.ownerName
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return String(localized: "Connected") }
        return String(localized: "Connected as \(name)", comment: "Connect to company: whose phone this is on the company's website; the value is a person's name")
    }

    private var lastSynced: String {
        guard let date = connect.state.lastSyncedAt else { return String(localized: "Not yet") }
        return date.formatted(.relative(presentation: .named))
    }

    private var disconnectTitle: String {
        let company = connect.account?.companyName ?? ""
        return String(
            localized: "Disconnect from \(company)?",
            comment: "Connect to company: asked before disconnecting; the value is the company's name"
        )
    }

    private var sentFooter: String {
        let host = connect.account?.host ?? ""
        return String(
            localized: "Sent to \(host) only: the site days, month sheets, sign-offs, extra work, defects, Missing and deliveries of the company's sites and of the sites switched on above. Your own hours, your pay and your other sites stay on this phone. The phone's key is kept in its Keychain, never in a backup.",
            comment: "Connect to company, the footer when connected; the value is the company's website"
        )
    }
}

/// An address and a code, to be confirmed before pairing.
struct ConnectPairingRequest: Identifiable, Hashable {
    var url: URL
    var code: String
    var id: String { url.absoluteString + code }
}

/// The QR code on the company's website, read with the camera scanner the
/// barcode screens use. Where the camera cannot run, it says so: the
/// address and the code can be typed.
struct ConnectScanSheet: View {
    let onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraIsAvailable = BarcodeScanning.cameraIsAvailable
    @State private var handled = false

    var body: some View {
        NavigationStack {
            Group {
                if cameraIsAvailable {
                    BarcodeCameraView(isPaused: handled) { value, _ in
                        guard !handled else { return }
                        handled = true
                        onCode(value)
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "The camera is not available",
                        systemImage: "camera",
                        description: Text("Type the website address and the code instead.")
                    )
                }
            }
            .navigationTitle("Scan the QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("connect-scan-cancel")
                }
            }
            .task {
                await BarcodeScanning.requestCameraIfNeeded()
                cameraIsAvailable = BarcodeScanning.cameraIsAvailable
            }
        }
    }
}

/// On a site's page: that it came from the company, and what the office
/// sent back or wrote about it.
struct ConnectSiteSection: View {
    let siteID: UUID

    var body: some View {
        let connect = HoursStack.connect
        let company = connect.companyName(forSite: siteID)
        let returns = connect.returns(onSite: siteID)
        let notes = Array(connect.notes(onSite: siteID).prefix(3))
        if company != nil || !returns.isEmpty || !notes.isEmpty {
            Section {
                ForEach(returns, id: \.self) { item in
                    Label {
                        Text(verbatim: ConnectText.returned(item.comment))
                    } icon: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(Color.hoursAttention)
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("site-office-return")
                }
                ForEach(notes, id: \.id) { note in
                    Label {
                        Text(verbatim: note.body)
                    } icon: {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.hoursSecondaryText)
                    }
                    .font(.subheadline)
                }
                if let company {
                    Label {
                        Text(verbatim: String(localized: "From \(company)", comment: "A site that came from the company's website; the value is the company's name"))
                    } icon: {
                        Image(systemName: "building.columns")
                    }
                    .font(.footnote)
                    .foregroundStyle(.hoursSecondaryText)
                    .accessibilityIdentifier("site-from-company")
                }
            }
        }
    }
}

/// On a site day: what the office said about it, and whether it went.
struct ConnectDaySection: View {
    let siteID: UUID
    let date: CalendarDate

    var body: some View {
        let connect = HoursStack.connect
        if let status = connect.status(ofDayOn: siteID, date: date), status != .notSent {
            let comments = connect.state.comments(on: .siteDay, id: ConnectID.string(ConnectUUID.siteDayID(siteID: siteID, date: date)))
            Section {
                ConnectStatusLine(status: status)
                ForEach(comments.filter { $0.purpose != "return" }, id: \.id) { comment in
                    Label {
                        Text(verbatim: comment.body)
                    } icon: {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.hoursSecondaryText)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}

/// "Sent", "Waiting to send", "Approved", "Returned by the office: …".
struct ConnectStatusLine: View {
    let status: ConnectRecordStatus

    var body: some View {
        switch status {
        case .notSent:
            EmptyView()
        case .waiting:
            Label("Waiting to send", systemImage: "clock")
                .font(.footnote)
                .foregroundStyle(.hoursSecondaryText)
                .accessibilityIdentifier("connect-line-waiting")
        case .sent:
            Label("Sent", systemImage: "checkmark")
                .font(.footnote)
                .foregroundStyle(.hoursSecondaryText)
                .accessibilityIdentifier("connect-line-sent")
        case .approved:
            Label {
                Text("Approved")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.hoursDone)
            }
            .font(.footnote)
            .accessibilityIdentifier("connect-line-approved")
        case let .returned(comment):
            Label {
                Text(verbatim: ConnectText.returned(comment))
            } icon: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(Color.hoursAttention)
            }
            .font(.subheadline)
            .accessibilityIdentifier("connect-line-returned")
        }
    }
}

/// The words for what the connection says.
enum ConnectText {
    static func returned(_ comment: String?) -> String {
        guard let comment = comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty else {
            return String(localized: "Returned by the office. Correct it and send it again.")
        }
        return String(localized: "Returned by the office: \(comment)", comment: "A sheet or a day sent back by the office; the value is the office's comment")
    }

    static func problem(_ error: ConnectError) -> String {
        switch error {
        case .offline:
            return String(localized: "The company's website can't be reached. Nothing is lost; it tries again by itself.")
        case .revoked:
            return String(localized: "This phone was disconnected by the office.")
        case .unauthorized:
            return String(localized: "The website did not accept this phone. Connect it again.")
        case .pairingCodeInvalid:
            return String(localized: "That code is not right. Ask the office for a new one.")
        case .pairingCodeExpired:
            return String(localized: "That code has run out. Ask the office for a new one.")
        case .pairingCodeUsed:
            return String(localized: "That code was already used. Ask the office for a new one.")
        case .rateLimited, .server, .conflict:
            return String(localized: "The company's website is busy. It tries again by itself.")
        case .unsupportedVersion:
            return String(localized: "This code needs a newer Zeitkonto. Update the app first.")
        case .badAddress:
            return String(localized: "That is not a website address.")
        case .payloadTooLarge, .validationFailed, .refused, .unreadable:
            return String(localized: "The company's website refused something. The rest was sent.")
        }
    }

    static func closedMonth(_ conflict: ConnectMergeConflict, formatting: CalendarFormatting) -> String {
        let month = ConnectFormat.parseMonth(conflict.month).map(formatting.monthTitle) ?? conflict.month
        switch conflict.kind {
        case .returnedInClosedMonth:
            return String(localized: "Returned for \(month), which is closed. Reopen the month to correct it.", comment: "Connect to company; the value is a month and year")
        case .siteRemovedWithClosedMonth:
            return String(localized: "A site with days in \(month), which is closed, was removed by the office. It is archived here, with its days.", comment: "Connect to company; the value is a month and year")
        case .personRemovedWithClosedMonth:
            return String(localized: "Someone with days in \(month), which is closed, was removed by the office. Their days stay.", comment: "Connect to company; the value is a month and year")
        }
    }
}
