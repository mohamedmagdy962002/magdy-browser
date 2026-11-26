import Foundation
import UIKit

/// Offline reading list screen.
final class ReadingListViewController: UITableViewController {

    private let store = ReadingListStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Reading List"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(clearAll)
        )
    }

    @objc private func clearAll() {
        for item in store.items { store.remove(item) }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = store.items[indexPath.row]
        cell.backgroundColor = Theme.card
        cell.layer.cornerRadius = Theme.corner
        cell.layer.cornerCurve = .continuous
        var content = cell.defaultContentConfiguration()
        content.text = item.title.isEmpty ? "Untitled" : item.title
        content.textProperties.font = Theme.body(15, weight: .semibold)
        content.secondaryText = "\(item.paragraphs.count) paragraphs · saved offline"
        content.secondaryTextProperties.color = Theme.textSecondary
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = store.items[indexPath.row]
        let article = ReaderMode.Article(title: item.title, paragraphs: item.paragraphs)
        let reader = ReaderViewController(article: article)
        let navigation = UINavigationController(rootViewController: reader)
        present(navigation, animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let item = store.items[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.store.remove(item)
            self?.tableView.reloadData()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}
