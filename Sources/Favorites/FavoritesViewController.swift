import UIKit

final class FavoritesViewController: UITableViewController {
    private let store = FavoritesStore.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.t("favorites")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        store.favorites.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let favorite = store.favorites[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = favorite.title
        content.textProperties.font = Theme.body(15, weight: .semibold)
        content.secondaryText = favorite.url
        content.secondaryTextProperties.color = Theme.textSecondary
        cell.contentConfiguration = content
        cell.backgroundColor = Theme.card
        cell.layer.cornerRadius = Theme.corner
        cell.layer.cornerCurve = .continuous
        cell.selectionStyle = .none
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let favorite = store.favorites[indexPath.row]
        guard let url = URL(string: favorite.url) else { return }
        NotificationCenter.default.post(name: .magdyOpenURL, object: url)
        tabBarController?.selectedIndex = 0
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.store.remove(at: indexPath.row)
            self?.tableView.reloadData()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        store.favorites.isEmpty ? "No favorites yet." : nil
    }
}
