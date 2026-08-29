import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Backup, restore and deletion.
struct DataSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext

    @State private var backupURL: URL?
    @State private var isImporting = false
    @State private var isConfirmingDelete = false
    @State private var pendingRestore: BackupArchive?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                LabeledContent("Days recorded", value: "\(dayCount)")
                LabeledContent("Holidays", value: "\(holidayCount)")
                if let bounds = repository.recordedDateBounds() {
                    LabeledContent(
                        "Covering",
                        value: "\(settingsStore.dateFormatting.mediumDate(bounds.first)) – \(settingsStore.dateFormatting.mediumDate(bounds.last))"
                    )
                }
            } header: {
                Text("Stored on this device")
            }

            Section {
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("Share backup", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    createBackup()
                } label: {
                    Label(backupURL == nil ? "Create a backup" : "Create a fresh backup", systemImage: "externaldrive.badge.plus")
                }
                Button {
                    isImporting = true
                } label: {
                    Label("Restore from a backup", systemImage: "arrow.down.doc")
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup is a JSON file containing every day, every holiday and all your settings. Nothing is uploaded — you choose where the file goes.")
            }

            Section {
                Button("Delete all data", role: .destructive) {
                    isConfirmingDelete = true
                }
            } footer: {
                Text("Removes every recorded day and holiday from this device. Settings are kept.")
            }

            if let message {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Backup and data")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .confirmationDialog(
            "Delete every recorded day and holiday?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Create a backup first if you are not sure.")
        }
        // An alert rather than a second confirmation dialog: two dialogs of the
        // same kind on one view is undefined behaviour.
        .alert(
            "Replace everything on this device with the backup?",
            isPresented: restoreConfirmationBinding,
            presenting: pendingRestore
        ) { archive in
            Button("Replace", role: .destructive) { applyRestore(archive) }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: { archive in
            // Text's LocalizedStringKey goes through the same absent table as
            // String(localized:), so this needs resolving before it is handed
            // over rather than after.
            Text(String(
                inflected: "The backup holds ^[\(archive.days.count) day](inflect: true) and ^[\(archive.holidays.count) holiday](inflect: true).\(damageWarning(for: archive)) Everything currently stored will be removed."
            ))
        }
    }

    // MARK: - Derived

    private var repository: WorkdayRepository { WorkdayRepository(context: modelContext) }
    private var dayCount: Int { repository.allEntries().count }
    private var holidayCount: Int { repository.holidayRecords().count }

    private var restoreConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingRestore != nil },
            set: { isPresented in if !isPresented { pendingRestore = nil } }
        )
    }

    // MARK: - Actions

    private func createBackup() {
        let archive = BackupArchive(
            settings: settingsStore.settings,
            days: repository.allEntries().map(\.record),
            holidays: repository.holidayRules()
        )
        do {
            let data = try archive.encoded()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter.backupStamp.string(from: archive.exportedAt)
            let url = directory.appendingPathComponent("Zeitkonto backup \(stamp).json")
            try data.write(to: url, options: .atomic)
            backupURL = url
            message = String(inflected: "Backup ready: ^[\(archive.days.count) day](inflect: true).")
        } catch {
            message = "The backup could not be created. \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            // A file picked from another app arrives security-scoped.
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let archive = try BackupArchive.decoded(from: try Data(contentsOf: url))
                pendingRestore = archive
            } catch {
                message = String(
                    localized: "That file could not be read as a backup. \(error.localizedDescription)",
                    comment: "Restore failed; the value is the system's own description"
                )
            }
        case let .failure(error):
            message = String(
                localized: "The file could not be opened. \(error.localizedDescription)",
                comment: "The file picker failed; the value is the system's own description"
            )
        }
    }

    /// What to say about days the backup file holds but could not be read.
    ///
    /// Said before the restore rather than after, because after is too late:
    /// this is the sentence that lets someone cancel, go and find a better copy
    /// of the file, and keep what is still on the device.
    private func damageWarning(for archive: BackupArchive) -> String {
        guard archive.hasDamage else { return "" }
        return " " + String(
            inflected: "^[\(archive.damagedDays.count) day](inflect: true) in the file is damaged and will not be restored."
        )
    }

    /// The damaged days, named, so they can be re-entered by hand.
    ///
    /// Capped: a badly damaged file could name hundreds, and a message nobody
    /// can read is the same as no message.
    private func damageDetail(for archive: BackupArchive) -> String {
        let formatting = settingsStore.dateFormatting
        let named = archive.damagedDays.compactMap { day -> String? in
            if case let .dated(date) = day { return formatting.mediumDate(date) }
            return nil
        }
        let unidentified = archive.damagedDays.count - named.count

        var parts: [String] = []
        if !named.isEmpty {
            let shown = named.prefix(8).joined(separator: ", ")
            parts.append(named.count > 8 ? String(
            localized: "\(shown) and \(named.count - 8) more",
            comment: "A truncated list; the first value is the list so far"
        ) : shown)
        }
        if unidentified > 0 {
            parts.append(String(inflected: "^[\(unidentified) day](inflect: true) with no readable date"))
        }
        return parts.joined(separator: ", plus ")
    }

    private func applyRestore(_ archive: BackupArchive) {
        pendingRestore = nil

        // Nothing in, nothing destroyed. A backup with no days in it can only
        // erase, and there is already a button for erasing that says so. The
        // decoder now refuses damaged files, which is what made this reachable
        // in the first place; this is the second lock on the same door,
        // because the thing behind it is every hour the person ever recorded.
        guard !archive.days.isEmpty || !archive.holidays.isEmpty else {
            // A file whose every day is damaged is not an empty file, and
            // saying "holds no days" about it would be a lie that costs the
            // person the chance to look for a better copy.
            message = archive.hasDamage
                ? String(inflected: "Nothing was restored: all ^[\(archive.damagedDays.count) day](inflect: true) in that file are damaged. Your existing hours have not been touched.")
                : "That backup holds no days, so nothing was changed. Use “Delete everything” if you meant to start over."
            return
        }

        repository.deleteAllDays()
        repository.deleteAllHolidays()
        // Unlocked on purpose. A restore is not an edit to a closed month; it
        // is the file becoming the database, and refusing half of it would
        // leave a mixture of the backup and what was there before.
        let restoring = WorkdayRepository(context: modelContext, lock: .unlocked)
        for record in archive.days { try? restoring.save(record) }
        for holiday in archive.holidays { repository.upsert(holiday) }
        settingsStore.replace(with: archive.settings)

        HoursStack.refreshWidget()

        var restored = String(
            inflected: "Restored ^[\(archive.days.count) day](inflect: true) and ^[\(archive.holidays.count) holiday](inflect: true)."
        )
        if archive.hasDamage {
            // Named, not just counted. A count tells someone they have lost
            // something; the dates tell them what to go and type back in.
            restored += " " + String(
                inflected: "^[\(archive.damagedDays.count) day](inflect: true) could not be read and was not restored: \(damageDetail(for: archive))."
            )
        }
        message = restored
    }

    private func deleteAll() {
        repository.deleteAllDays()
        repository.deleteAllHolidays()
        HoursStack.refreshWidget()
        message = String(localized: "All recorded days and holidays were removed.")
    }
}

private extension ISO8601DateFormatter {
    /// `2026-08-25` — sortable, and legal in a filename on every system the
    /// file might end up on.
    static let backupStamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
