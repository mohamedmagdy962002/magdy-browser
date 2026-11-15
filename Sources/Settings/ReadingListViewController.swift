import Foundation
import UIKit

/// Save-for-later articles, stored offline in the app sandbox.
final class ReadingListStore {
    struct Item: Codable {
        let id: UUID
        var title: String
        var url: String
        var paragraphs: [String]
        var addedAt: Date
    }

    static let shared = ReadingListStore()

    private let key = "magdy.readingList"

    private(set) var items: [Item] = []

    init() {
        load()
    }

    func add(title: String, url: String, paragraphs: [String]) {
        let item = Item(id: UUID(), title: title, url: url, paragraphs: paragraphs, addedAt: Date())
        items.insert(item, at: 0)
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Re-reads from disk (used after a backup restore so the UI and next save see restored data).
    func reloadFromDisk() {
        load()
    }
}

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
