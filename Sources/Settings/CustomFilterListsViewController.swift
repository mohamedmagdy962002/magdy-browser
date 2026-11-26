import UIKit
import WebKit

/// Add and manage filter list subscriptions by URL.
final class CustomFilterListsViewController: UITableViewController {

    private let store = CustomFilterListStore.shared
    private let manager = FilterListManager.shared
    private var observer: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Custom Lists"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
        observer = manager.observe { [weak self] in
            DispatchQueue.main.async { self?.tableView.reloadData() }
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addTapped)
        )
    }

    deinit {
        if let observer { manager.removeObserver(observer) }
    }

    @objc private func addTapped() {
        let alert = UIAlertController(title: "Add Filter List", message: "Paste an Adblock Plus list URL.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "List name"
        }
        alert.addTextField { field in
            field.placeholder = "https://example.com/list.txt"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let self else { return }
            let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let urlString = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty,
                  let url = URL.webURL(from: urlString),
                  url.scheme?.lowercased() == "https" else {
                self.showAlert(title: "Invalid list", message: "Enter a name and a valid HTTPS URL.")
                return
            }
            self.store.add(name: name, url: url.absoluteString)
            guard let added = self.store.entries.last else { return }
            let id = "custom.\(added.id.uuidString)"
            self.tableView.reloadData()
            self.store.download(added) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let text):
                        self.manager.compileCustomText(id: id, text: text) { [weak self] success in
                            guard let self else { return }
                            if success {
                                self.manager.setCustomList(id, enabled: true)
                            } else {
                                self.showAlert(title: "Compilation failed", message: "The list could not be enabled. Try another source.")
                            }
                            self.tableView.reloadData()
                        }
                    case .failure:
                        self.showAlert(title: "Download failed", message: "The list must be HTTPS and no larger than 50 MB.")
                    }
                }
            }
        })
        alert.addAction(UIAlertAction(title: L.t("cancel"), style: .cancel))
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.entries.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let entry = store.entries[indexPath.row]
        cell.backgroundColor = Theme.card
        cell.layer.cornerRadius = Theme.corner
        cell.layer.cornerCurve = .continuous
        var content = cell.defaultContentConfiguration()
        content.text = entry.name
        content.textProperties.font = Theme.body(15, weight: .semibold)
        let id = "custom.\(entry.id.uuidString)"
        content.secondaryText = manager.failedIDs.contains(id) ? "Unavailable — tap to retry" : entry.url
        content.secondaryTextProperties.color = Theme.textSecondary
        content.secondaryTextProperties.numberOfLines = 1
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = manager.activeCustomIDs.contains("custom.\(entry.id.uuidString)")
        toggle.accessibilityIdentifier = "custom.\(entry.id.uuidString)"
        toggle.onTintColor = Theme.primary
        toggle.addTarget(self, action: #selector(toggled(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    @objc private func toggled(_ sender: UISwitch) {
        guard let id = sender.accessibilityIdentifier else { return }
        manager.setCustomList(id, enabled: sender.isOn)
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let id = "custom.\(store.entries[indexPath.row].id.uuidString)"
        guard manager.failedIDs.contains(id), manager.activeCustomIDs.contains(id) else { return }
        manager.compileEnabled()
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let entry = store.entries[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else { return }
            self.store.remove(entry)
            self.manager.removeRuleList(withIdentifier: "custom.\(entry.id.uuidString)")
            self.tableView.reloadData()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
        present(alert, animated: true)
    }
}
