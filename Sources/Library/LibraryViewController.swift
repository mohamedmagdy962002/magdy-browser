import UIKit

final class LibraryViewController: UITableViewController {
    private enum Item: CaseIterable {
        case downloads, favorites, history

        var route: AppRoute {
            switch self {
            case .downloads: return .downloads
            case .favorites: return .favorites
            case .history: return .history
            }
        }

        var subtitle: String {
            switch self {
            case .downloads:
                let items = DownloadManager.shared.items
                let active = items.filter { $0.state == .running || $0.state == .paused }.count
                return active > 0 ? "\(items.count) · \(active) active" : "\(items.count)"
            case .favorites:
                let count = FavoritesStore.shared.favorites.count
                let folders = FavoritesStore.shared.folders().count
                return folders > 0 ? "\(count) · \(folders) folders" : "\(count)"
            case .history:
                return "\(HistoryStore.shared.entries.count)"
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.t("library")
        view.accessibilityIdentifier = "library-screen"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        navigationController?.navigationBar.prefersLargeTitles = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    func refreshLocalizedContent() {
        guard isViewLoaded else { return }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Item.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = Item.allCases[indexPath.row]
        var content = UIListContentConfiguration.valueCell()
        content.text = item.route.title
        content.textProperties.font = Theme.headline(17, weight: .semibold)
        content.secondaryText = item.subtitle
        content.secondaryTextProperties.font = Theme.footnote
        content.secondaryTextProperties.color = Theme.textSecondary
        content.image = UIImage(systemName: item.route.systemImage)
        content.imageProperties.tintColor = Theme.accentText
        content.imageProperties.maximumSize = CGSize(width: 28, height: 28)
        cell.contentConfiguration = content
        cell.backgroundColor = Theme.card
        cell.layer.cornerRadius = Theme.corner
        cell.layer.cornerCurve = .continuous
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "library-\(item.route.rawValue)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        appRouteHandler?.navigate(to: Item.allCases[indexPath.row].route)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        L.t("your_collection")
    }

}
