import UIKit

final class HistoryViewController: UITableViewController {
    private let store = HistoryStore.shared
    private var entries: [HistoryEntry] = []
    private let searchController = UISearchController(searchResultsController: nil)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "History"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Clear", style: .plain, target: self, action: #selector(clearAll)
        )
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        entries = store.search(searchController.searchBar.text ?? "")
        tableView.reloadData()
    }

    @objc private func clearAll() {
        let alert = UIAlertController(
            title: "Clear history?",
            message: "This removes every visited page stored on this device.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            self?.store.clear()
            self?.reload()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = navigationItem.rightBarButtonItem?.customView
        }
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let entry = entries[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = entry.title
        content.secondaryText = entry.url
        content.imageProperties.maximumSize = CGSize(width: 32, height: 32)
        content.image = UIImage(systemName: "globe")
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = entries[indexPath.row]
        guard let url = URL(string: entry.url) else { return }
        NotificationCenter.default.post(name: .magdyOpenURL, object: url)
        tabBarController?.selectedIndex = 0
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.store.remove(at: indexPath.row)
            self?.reload()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        entries.isEmpty ? "Nothing visited yet." : nil
    }
}

extension HistoryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        reload()
    }
}
