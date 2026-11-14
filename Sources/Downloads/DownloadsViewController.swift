import UIKit

final class DownloadsViewController: UITableViewController {
    private let manager = DownloadManager.shared
    private var items: [DownloadItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.t("downloads")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 76
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L.t("clear"),
            style: .plain,
            target: self,
            action: #selector(clearFinished)
        )
        manager.onChange = { [weak self] in self?.reload() }
        reload()
    }

    private func reload() {
        items = manager.items
        tableView.reloadData()
    }

    @objc private func clearFinished() {
        manager.clearFinished()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = items[indexPath.row]

        cell.backgroundColor = Theme.card
        cell.layer.cornerRadius = Theme.corner
        cell.layer.cornerCurve = .continuous
        cell.layer.masksToBounds = false
        cell.selectionStyle = .none

        var content = cell.defaultContentConfiguration()
        content.text = item.fileName
        content.textProperties.font = Theme.body(15, weight: .semibold)
        content.textProperties.color = Theme.textPrimary
        content.secondaryTextProperties.color = Theme.textSecondary
        switch item.state {
        case .finished:
            content.secondaryText = ByteCountFormatter.string(fromByteCount: item.bytesWritten, countStyle: .file)
        case .failed:
            content.secondaryText = item.errorMessage ?? "Failed"
        case .cancelled:
            content.secondaryText = "Cancelled"
        case .paused:
            content.secondaryText = "Paused · \(Int(item.progress * 100))%"
        default:
            content.secondaryText = item.totalBytes > 0
                ? "\(Int(item.progress * 100))% · \(ByteCountFormatter.string(fromByteCount: item.bytesWritten, countStyle: .file))"
                : "Starting…"
        }
        cell.contentConfiguration = content
        cell.accessoryType = item.state == .finished ? .disclosureIndicator : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        guard item.state == .finished, let localURL = item.localURL else { return }
        let sheet = UIActivityViewController(activityItems: [localURL], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
        present(sheet, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let item = items[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, completion in
            self.manager.remove(item)
            completion(true)
        }
        let actions = [delete]
        if item.state == .running {
            let cancel = UIContextualAction(style: .normal, title: "Cancel") { _, _, completion in
                self.manager.cancel(item)
                completion(true)
            }
            cancel.backgroundColor = .systemOrange
            let pause = UIContextualAction(style: .normal, title: "Pause") { _, _, completion in
                self.manager.pause(item)
                completion(true)
            }
            pause.backgroundColor = .systemBlue
            return UISwipeActionsConfiguration(actions: [delete, cancel, pause])
        }
        if item.state == .paused {
            let resume = UIContextualAction(style: .normal, title: "Resume") { _, _, completion in
                self.manager.resume(item)
                completion(true)
            }
            resume.backgroundColor = .systemGreen
            return UISwipeActionsConfiguration(actions: [delete, resume])
        }
        return UISwipeActionsConfiguration(actions: actions)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        items.isEmpty ? "No downloads yet — unlimited, no caps." : nil
    }
}
