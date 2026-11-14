import UIKit

/// Favorites manager: search, add, edit, reorder. The first 8 favorites power the speed dial.
final class FavoritesViewController: UITableViewController {
    private let store = FavoritesStore.shared
    private var items: [Favorite] = []
    private let searchController = UISearchController(searchResultsController: nil)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.t("favorites")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addTapped)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        items = store.search(searchController.searchBar.text ?? "")
        tableView.reloadData()
    }

    @objc private func addTapped() {
        editFavorite(nil)
    }

    private func editFavorite(_ favorite: Favorite?) {
        let alert = UIAlertController(
            title: favorite == nil ? "Add Favorite" : "Edit Favorite",
            message: "Favorites appear on the speed dial.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Title"
            field.text = favorite?.title
        }
        alert.addTextField { field in
            field.placeholder = "https://example.com"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.text = favorite?.url
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let title = alert.textFields?[0].text ?? ""
            let urlString = alert.textFields?[1].text ?? ""
            if let favorite,
               let index = self.store.favorites.firstIndex(where: { $0.url == favorite.url }) {
                self.store.update(at: index, title: title, urlString: urlString)
            } else {
                self.store.add(urlString: urlString, title: title)
            }
            self.reload()
        })
        alert.addAction(UIAlertAction(title: L.t("cancel"), style: .cancel))
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let favorite = items[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = favorite.title
        content.textProperties.font = Theme.body(15, weight: .semibold)
        content.secondaryText = favorite.url
        content.secondaryTextProperties.color = Theme.textSecondary
        content.image = UIImage(systemName: "star.fill")
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
        guard let url = URL(string: items[indexPath.row].url) else { return }
        NotificationCenter.default.post(name: .magdyOpenURL, object: url)
        tabBarController?.selectedIndex = 0
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let favorite = items[indexPath.row]
        let edit = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, completion in
            self?.editFavorite(favorite)
            completion(true)
        }
        edit.backgroundColor = .systemBlue
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self,
                  let index = self.store.favorites.firstIndex(where: { $0.url == favorite.url }) else {
                completion(true)
                return
            }
            self.store.remove(at: index)
            self.reload()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }

    override func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard searchController.searchBar.text?.isEmpty != false else { return }
        store.move(from: sourceIndexPath.row, to: destinationIndexPath.row)
        reload()
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        true
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        items.isEmpty ? "No favorites yet — tap + to add. First 8 show on the speed dial." : nil
    }
}

extension FavoritesViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        reload()
    }
}
