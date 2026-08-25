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
            Text("The backup holds \(archive.days.count) days and \(archive.holidays.count) holidays. Everything currently stored will be removed.")
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
            let url = directory.appendingPathComponent("Hours backup \(stamp).json")
            try data.write(to: url, options: .atomic)
            backupURL = url
            message = "Backup ready: \(archive.days.count) days."
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
                message = "That file could not be read as a backup. \(error.localizedDescription)"
            }
        case let .failure(error):
            message = "The file could not be opened. \(error.localizedDescription)"
        }
    }

    private func applyRestore(_ archive: BackupArchive) {
        pendingRestore = nil

        repository.deleteAllDays()
        repository.deleteAllHolidays()
        for record in archive.days { repository.save(record) }
        for holiday in archive.holidays { repository.upsert(holiday) }
        settingsStore.replace(with: archive.settings)

        message = "Restored \(archive.days.count) days and \(archive.holidays.count) holidays."
    }

    private func deleteAll() {
        repository.deleteAllDays()
        repository.deleteAllHolidays()
        message = "All recorded days and holidays were removed."
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
