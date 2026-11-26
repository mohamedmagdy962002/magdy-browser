import UIKit
import UniformTypeIdentifiers

/// Backup of magdy.* preferences, favorites, reading list, history and filter selections.
/// Vault media, downloads and custom-filter file contents are deliberately not included.
enum BackupRestore {

    struct Backup: Codable {
        let version: Int
        /// Plist-encoded values for backed-up "magdy.*" UserDefaults keys.
        let defaults: [String: Data]
        /// Raw history.json content.
        let history: Data?
    }

    struct RestoreResult {
        let failures: [String]
        let omittedData: [String]
        var isSuccess: Bool { failures.isEmpty }
    }

    private struct StagedBackup {
        let defaults: [String: Any]
        let history: Data?
        let omittedData: [String]
    }

    private enum BackupError: Error, CustomStringConvertible {
        case invalidVersion(Int)
        case invalidName(String)
        case invalidPropertyList(String)
        case unsupportedValue(String)
        case invalidHistory
        case invalidPayload(String)
        case backupTooLarge
        case missingPreferenceDomain
        case verificationFailed(String)
        case historyWriteFailed

        var description: String {
            switch self {
            case .invalidVersion(let version): return "Unsupported backup schema version \(version)."
            case .invalidName(let name): return "Invalid preference name: \(name)."
            case .invalidPropertyList(let name): return "Invalid property-list data for \(name)."
            case .unsupportedValue(let name): return "Unsupported preference value for \(name)."
            case .invalidHistory: return "The history payload is not valid history JSON."
            case .invalidPayload(let name): return "Invalid backup payload for \(name)."
            case .backupTooLarge: return "The backup is too large to restore safely."
            case .missingPreferenceDomain: return "The app preference domain is unavailable."
            case .verificationFailed(let name): return "Could not verify the restored preference \(name)."
            case .historyWriteFailed: return "History could not be saved."
            }
        }
    }

    private static let version = 1
    private static let maxBackupBytes = 25_000_000
    private static let omittedDataNotice = "Vault media, downloads and custom-filter files are not included in backups."
    private static let excludedPreferenceKeys: Set<String> = [
        "magdy.vault.entries",
        "magdy.customFilterLists",
        "magdy.customFilterLists.enabled",
        DownloadManager.folderBookmarkKey
    ]

    static func exportData() -> Data? {
        var payload: [String: Data] = [:]
        do {
            for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("magdy.") {
                guard !isExcludedPreference(key) else { continue }
                guard isSafePreferenceName(key) else { throw BackupError.invalidName(key) }
                let encoded = try PropertyListSerialization.data(
                    fromPropertyList: value, format: .binary, options: 0
                )
                let roundTripped = try PropertyListSerialization.propertyList(from: encoded, options: [], format: nil)
                try validatePreferencePayload(key, value: roundTripped)
                payload[key] = encoded
            }
            guard let history = HistoryStore.shared.exportData() else { return nil }
            let backup = Backup(version: version, defaults: payload, history: history)
            return try JSONEncoder().encode(backup)
        } catch {
            return nil
        }
    }

    /// Source-compatible Boolean API. False means validation or restore failed;
    /// use restoreWithResult for the exact failure and omission details.
    @discardableResult
    static func restore(from data: Data) -> Bool {
        restoreWithResult(from: data).isSuccess
    }

    /// Validates every payload before changing state, applies the preference
    /// domain in one replacement, writes history atomically, and rolls back on failure.
    static func restoreWithResult(from data: Data) -> RestoreResult {
        let staged: StagedBackup
        do {
            staged = try stage(data)
        } catch {
            return RestoreResult(
                failures: ["Invalid backup: \(error)"],
                omittedData: [omittedDataNotice]
            )
        }

        let defaults = UserDefaults.standard
        guard let domainName = Bundle.main.bundleIdentifier, !domainName.isEmpty else {
            return RestoreResult(
                failures: ["Restore failed: \(BackupError.missingPreferenceDomain)"],
                omittedData: staged.omittedData
            )
        }
        let originalDomain = defaults.persistentDomain(forName: domainName)
        let rollbackDomain = originalDomain ?? [:]
        guard let originalHistory = HistoryStore.shared.exportData() else {
            return RestoreResult(
                failures: ["Restore failed: the current history could not be staged."],
                omittedData: staged.omittedData
            )
        }

        do {
            try applyDefaults(staged.defaults, to: rollbackDomain, domainName: domainName)
            if let history = staged.history {
                guard HistoryStore.shared.restoreData(history) else {
                    throw BackupError.historyWriteFailed
                }
            }
        } catch {
            var failures = ["Restore failed: \(error)"]
            var rollbackFailures: [String] = []
            do {
                try rollbackDefaults(rollbackDomain, hadOriginalDomain: originalDomain != nil,
                                     keys: Array(staged.defaults.keys), domainName: domainName)
            } catch {
                rollbackFailures.append("Defaults rollback failed: \(error)")
            }
            if staged.history != nil, !HistoryStore.shared.restoreData(originalHistory) {
                rollbackFailures.append("History rollback failed: the previous history could not be saved.")
            }
            failures.append(contentsOf: rollbackFailures)
            return RestoreResult(failures: failures, omittedData: staged.omittedData)
        }

        // Singleton stores cache state at init — make them see restored data now,
        // otherwise the next save would silently overwrite it.
        FavoritesStore.shared.reloadFromDisk()
        ReadingListStore.shared.reloadFromDisk()
        NotificationCenter.default.post(name: .magdyThemeChanged, object: nil)
        NotificationCenter.default.post(name: .magdyBlockStatsChanged, object: nil)
        FilterListManager.shared.compileEnabled()
        return RestoreResult(failures: [], omittedData: staged.omittedData)
    }

    static func suggestedFileName() -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        return "MagdyBrowser-Backup-\(stamp.string(from: Date())).json"
    }

    // MARK: - Validation and staging

    private static func stage(_ data: Data) throws -> StagedBackup {
        guard data.count <= maxBackupBytes else { throw BackupError.backupTooLarge }
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        guard backup.version == version else { throw BackupError.invalidVersion(backup.version) }

        var defaults: [String: Any] = [:]
        var omitted = [omittedDataNotice]
        for (key, encoded) in backup.defaults {
            if isExcludedPreference(key) {
                omitted.append("Excluded vault, download and custom-filter references were ignored.")
                continue
            }
            guard isSafePreferenceName(key) else { throw BackupError.invalidName(key) }
            let value: Any
            do {
                value = try PropertyListSerialization.propertyList(from: encoded, options: [], format: nil)
            } catch {
                throw BackupError.invalidPropertyList(key)
            }
            guard isSupportedPreferenceValue(value) else { throw BackupError.unsupportedValue(key) }
            try validatePreferencePayload(key, value: value)
            defaults[key] = value
        }

        if let history = backup.history {
            guard let entries = try? JSONDecoder().decode([HistoryEntry].self, from: history),
                  entries.count <= 5000,
                  entries.allSatisfy({ URL(string: $0.url)?.isWebURL == true }) else {
                throw BackupError.invalidHistory
            }
        }
        return StagedBackup(defaults: defaults, history: backup.history, omittedData: omitted)
    }

    private static func isExcludedPreference(_ key: String) -> Bool {
        excludedPreferenceKeys.contains(key) || key.hasPrefix("magdy.playback.")
    }

    private static func isSafePreferenceName(_ name: String) -> Bool {
        let prefix = "magdy."
        guard name.hasPrefix(prefix), name.count > prefix.count,
              !name.contains("/"), !name.contains("\\"), !name.contains(".."), !name.utf8.contains(0),
              (name as NSString).pathComponents.count == 1,
              (name as NSString).lastPathComponent == name else { return false }
        return true
    }

    private static func validatePreferencePayload(_ key: String, value: Any) throws {
        switch key {
        case UserDefaultsKey.favorites:
            guard let data = value as? Data,
                  let favorites = try? JSONDecoder().decode([Favorite].self, from: data),
                  favorites.allSatisfy({ URL(string: $0.url)?.isWebURL == true }) else {
                throw BackupError.invalidPayload(key)
            }
        case "magdy.readingList":
            guard let data = value as? Data,
                  let items = try? JSONDecoder().decode([ReadingListStore.Item].self, from: data),
                  items.count <= 1000,
                  items.allSatisfy({
                      $0.url.isEmpty ? !$0.paragraphs.isEmpty : URL(string: $0.url)?.isWebURL == true
                  }) else {
                throw BackupError.invalidPayload(key)
            }
        case "magdy.session":
            guard let data = value as? Data,
                  let tabs = try? JSONDecoder().decode([TabStore.SavedTab].self, from: data),
                  tabs.count <= TabStore.maxSavedTabs,
                  tabs.allSatisfy({ URL.webURL(from: $0.url)?.absoluteString == $0.url }) else {
                throw BackupError.invalidPayload(key)
            }
        case "magdy.filterLists.enabled":
            guard let ids = value as? [String], ids.allSatisfy({ !$0.isEmpty }) else {
                throw BackupError.invalidPayload(key)
            }
        case "magdy.vault.entries":
            guard let names = value as? [String], names.allSatisfy({ isSafeBasename($0) }) else {
                throw BackupError.invalidPayload(key)
            }
        default:
            break
        }
    }

    private static func isSafeBasename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\") && !name.utf8.contains(0)
            && (name as NSString).pathComponents.count == 1
            && (name as NSString).lastPathComponent == name
    }

    private static func isSupportedPreferenceValue(_ value: Any) -> Bool {
        if value is String || value is Data || value is Date || value is NSNumber { return true }
        if let array = value as? [Any] { return array.allSatisfy({ isSupportedPreferenceValue($0) }) }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.allSatisfy({ isSupportedPreferenceValue($0) })
        }
        return false
    }

    // MARK: - Atomic preference-domain application

    private static func applyDefaults(_ values: [String: Any], to original: [String: Any], domainName: String) throws {
        guard !values.isEmpty else { return }
        var updated = original
        for (key, value) in values { updated[key] = value }
        UserDefaults.standard.setPersistentDomain(updated, forName: domainName)
        for key in values.keys {
            try verify(UserDefaults.standard.object(forKey: key), equals: values[key], key: key)
        }
    }

    private static func rollbackDefaults(
        _ original: [String: Any],
        hadOriginalDomain: Bool,
        keys: [String],
        domainName: String
    ) throws {
        if hadOriginalDomain {
            UserDefaults.standard.setPersistentDomain(original, forName: domainName)
        } else {
            UserDefaults.standard.removePersistentDomain(forName: domainName)
        }
        for key in keys {
            try verify(UserDefaults.standard.object(forKey: key), equals: original[key], key: key)
        }
    }

    private static func verify(_ actual: Any?, equals expected: Any?, key: String) throws {
        guard let actual else {
            if expected == nil { return }
            throw BackupError.verificationFailed(key)
        }
        guard let expected, (actual as? NSObject)?.isEqual(expected as? NSObject) == true else {
            throw BackupError.verificationFailed(key)
        }
    }
}

/// Settings screen for backup/restore: export via share sheet, import via Files picker.
final class BackupViewController: UITableViewController, UIDocumentPickerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Backup & Restore"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.row == 0 {
            content.text = "Export Backup"
            content.secondaryText = "Back up browser data (excludes vault media and downloads)"
            content.image = UIImage(systemName: "square.and.arrow.up")
        } else {
            content.text = "Import Backup"
            content.secondaryText = "Restore data from a backup file"
            content.image = UIImage(systemName: "square.and.arrow.down")
        }
        content.secondaryTextProperties.color = Theme.textSecondary
        content.textProperties.font = Theme.body(15, weight: .semibold)
        content.imageProperties.tintColor = Theme.primary
        cell.contentConfiguration = content
        cell.backgroundColor = Theme.card
        cell.layer.cornerRadius = Theme.corner
        cell.layer.cornerCurve = .continuous
        cell.selectionStyle = .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            exportBackup()
        } else {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
            picker.delegate = self
            if let popover = picker.popoverPresentationController {
                popover.sourceView = tableView.cellForRow(at: IndexPath(row: 1, section: 0)) ?? tableView
                popover.sourceRect = popover.sourceView?.bounds ?? tableView.bounds
            }
            present(picker, animated: true)
        }
    }

    private func exportBackup() {
        guard let data = BackupRestore.exportData() else {
            showAlert(title: "Export failed", message: "The backup could not be created.")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(BackupRestore.suggestedFileName())
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert(title: "Export failed", message: "The backup file could not be written.")
            return
        }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: IndexPath(row: 0, section: 0))
        sheet.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        present(sheet, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            showAlert(title: "Import failed", message: "The backup file could not be read.")
            return
        }

        let result = BackupRestore.restoreWithResult(from: data)
        guard result.failures.isEmpty else {
            showAlert(title: "Restore failed", message: result.failures.joined(separator: "\n\n"))
            return
        }
        let alert = UIAlertController(
            title: "Restored",
            message: "Settings, favorites, reading list, history and filter selections were restored.\n\n\(result.omittedData.joined(separator: "\n")) Restart the app to apply everything.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
        present(alert, animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
        present(alert, animated: true)
    }
}
