import UIKit
import UniformTypeIdentifiers

/// Full backup: every magdy.* preference, favorites, reading list, history, filters —
/// exported as one JSON file the user can share and re-import on another device.
enum BackupRestore {

    struct Backup: Codable {
        let version: Int
        /// Plist-encoded values for every "magdy.*" UserDefaults key.
        let defaults: [String: Data]
        /// Raw history.json content.
        let history: Data?
    }

    private static let version = 1

    static func exportData() -> Data? {
        var payload: [String: Data] = [:]
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() where key.hasPrefix("magdy.") {
            guard let data = try? PropertyListSerialization.data(
                fromPropertyList: value, format: .binary, options: 0
            ) else { continue }
            payload[key] = data
        }
        let backup = Backup(version: version, defaults: payload, history: HistoryStore.shared.exportData())
        return try? JSONEncoder().encode(backup)
    }

    /// Applies a backup. Returns false if the data isn't a valid backup.
    @discardableResult
    static func restore(from data: Data) -> Bool {
        guard let backup = try? JSONDecoder().decode(Backup.self, from: data) else { return false }
        let defaults = UserDefaults.standard
        for (key, encoded) in backup.defaults where key.hasPrefix("magdy.") {
            guard let value = try? PropertyListSerialization.propertyList(
                from: encoded, options: [], format: nil
            ) else { continue }
            // Values round-trip as NSNumber/String/Data/NSArray/NSDictionary — all valid UserDefaults types.
            defaults.set(value, forKey: key)
        }
        if let history = backup.history {
            HistoryStore.shared.restoreData(history)
        }
        // Observers on these notifications re-render the live screens.
        NotificationCenter.default.post(name: .magdyThemeChanged, object: nil)
        NotificationCenter.default.post(name: .magdyBlockStatsChanged, object: nil)
        FilterListManager.shared.compileEnabled()
        return true
    }

    static func suggestedFileName() -> String {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        return "MagdyBrowser-Backup-\(stamp.string(from: Date())).json"
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
            content.secondaryText = "Save all browser data to a file"
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
            present(picker, animated: true)
        }
    }

    private func exportBackup() {
        guard let data = BackupRestore.exportData() else {
            showAlert("Export failed")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(BackupRestore.suggestedFileName())
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert("Export failed")
            return
        }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: IndexPath(row: 0, section: 0))
        present(sheet, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first,
              let data = try? Data(contentsOf: url),
              BackupRestore.restore(from: data) else {
            showAlert("Not a valid backup file")
            return
        }
        let alert = UIAlertController(
            title: "Restored",
            message: "Favorites, history, reading list, filters and settings were restored. Restart the app to apply everything.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
        present(alert, animated: true)
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
        present(alert, animated: true)
    }
}
