import UIKit

/// Favorites manager: search, add, edit, reorder, folders.
/// Section 0 is the main list (first 8 favorites power the speed dial);
/// remaining sections are folders.
final class FavoritesViewController: UITableViewController {
    private let store = FavoritesStore.shared
    private var items: [Favorite] = []
    /// nil = showing all sections; non-nil = browsing inside a folder.
    private var openFolder: String?
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
        let searching = searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
        if searching, let text = searchController.searchBar.text, !text.isEmpty {
            items = store.search(text)
        } else if let openFolder {
            items = store.favorites(inFolder: openFolder)
        } else {
            items = store.favorites(inFolder: nil)
        }
        tableView.reloadData()
    }

    /// Items shown in the extra folder sections (only on the root view, not while searching).
    private var folderNames: [String] {
        let searching = searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
        return (openFolder == nil && !searching) ? store.folders() : []
    }

    @objc private func addTapped() {
        editFavorite(nil)
    }

    private func editFavorite(_ favorite: Favorite?) {
        let alert = UIAlertController(
            title: favorite == nil ? "Add Favorite" : "Edit Favorite",
            message: "Favorites without a folder appear on the speed dial.",
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
        alert.addTextField { field in
            field.placeholder = "Folder (optional)"
            field.text = favorite?.folder
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let title = alert.textFields?[0].text ?? ""
            let urlString = alert.textFields?[1].text ?? ""
            let folder = alert.textFields?[2].text
            if let favorite,
               let index = self.store.favorites.firstIndex(where: { $0.url == favorite.url }) {
                self.store.update(at: index, title: title, urlString: urlString, folder: folder)
            } else {
                self.store.add(urlString: urlString, title: title, folder: folder)
            }
            self.reload()
        })
        alert.addAction(UIAlertAction(title: L.t("cancel"), style: .cancel))
        present(alert, animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        1 + folderNames.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? items.count : store.favorites(inFolder: folderNames[section - 1]).count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section > 0 { return folderNames[section - 1] }
        if items.isEmpty && openFolder == nil {
            return "No favorites yet — tap + to add. First 8 show on the speed dial."
        }
        return nil
    }

    private func favorite(at indexPath: IndexPath) -> Favorite {
        indexPath.section == 0
            ? items[indexPath.row]
            : store.favorites(inFolder: folderNames[indexPath.section - 1])[indexPath.row]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let favorite = favorite(at: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = favorite.title
        content.textProperties.font = Theme.body(15, weight: .semibold)
        content.secondaryText = favorite.folder == nil ? favorite.url : favorite.url
        content.secondaryTextProperties.color = Theme.textSecondary
        content.image = UIImage(systemName: indexPath.section == 0 ? "star.fill" : "folder.fill")
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
        if indexPath.section > 0 {
            // Enter the folder.
            openFolder = folderNames[indexPath.section - 1]
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(backToFolders)
            )
            title = openFolder
            reload()
            return
        }
        guard let url = URL(string: items[indexPath.row].url) else { return }
        NotificationCenter.default.post(name: .magdyOpenURL, object: url)
        tabBarController?.selectedIndex = 0
    }

    @objc private func backToFolders() {
        openFolder = nil
        title = L.t("favorites")
        navigationItem.leftBarButtonItem = nil
        reload()
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let favorite = favorite(at: indexPath)
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
        guard sourceIndexPath.section == 0, destinationIndexPath.section == 0,
              searchController.searchBar.text?.isEmpty != false else { return }
        // Map the visible main-list row back to the store index.
        guard let storeIndex = store.favorites.firstIndex(where: { $0.url == items[sourceIndexPath.row].url }) else { return }
        let visible = store.favorites(inFolder: nil)
        var destination = destinationIndexPath.row
        if destination < visible.count, let targetIndex = store.favorites.firstIndex(where: { $0.url == visible[destination].url }) {
            destination = targetIndex
        } else {
            // End-of-list drop: after the last main-list item, skipping foldered entries.
            destination = (store.favorites.lastIndex { $0.folder == nil } ?? -1) + 1
        }
        store.move(from: storeIndex, to: destination)
        reload()
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Reordering is only meaningful on the unfiltered main list.
        indexPath.section == 0 && openFolder == nil && searchController.searchBar.text?.isEmpty != false
    }
}

extension FavoritesViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        reload()
    }
}
