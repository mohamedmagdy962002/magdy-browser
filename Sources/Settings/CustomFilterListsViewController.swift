import UIKit
import WebKit

/// Add and manage filter list subscriptions by URL.
final class CustomFilterListsViewController: UITableViewController {

    private let store = CustomFilterListStore.shared
    private let manager = FilterListManager.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Custom Lists"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addTapped)
        )
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
            guard let self,
                  let name = alert.textFields?[0].text, !name.isEmpty,
                  let urlString = alert.textFields?[1].text, !urlString.isEmpty else { return }
            let entry = self.store.entries.count
            self.store.add(name: name, url: urlString)
            self.tableView.reloadData()
            let added = self.store.entries[entry]
            self.store.download(added) { result in
                if case .success(let text) = result {
                    self.manager.compileCustomText(id: "custom.\(added.id.uuidString)", text: text)
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
        content.secondaryText = entry.url
        content.secondaryTextProperties.color = Theme.textSecondary
        content.secondaryTextProperties.numberOfLines = 1
        cell.contentConfiguration = content
        return cell
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
}
