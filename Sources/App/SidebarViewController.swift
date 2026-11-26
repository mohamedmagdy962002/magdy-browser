import UIKit

final class SidebarViewController: UITableViewController {
    var onSelect: ((AppRoute) -> Void)?
    private(set) var selectedRoute: AppRoute = .browser

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Magdy"
        view.accessibilityIdentifier = "app-sidebar"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = Theme.minimumTarget
        navigationController?.navigationBar.prefersLargeTitles = true
        tableView.reloadData()
    }

    func setSelectedRoute(_ route: AppRoute) {
        guard selectedRoute != route else { return }
        selectedRoute = route
        tableView.reloadData()
        if let row = AppRoute.primaryRoutes.firstIndex(of: route) {
            tableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        AppRoute.primaryRoutes.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let route = AppRoute.primaryRoutes[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = route.title
        content.textProperties.font = Theme.headline(17, weight: route == selectedRoute ? .semibold : .regular)
        content.image = UIImage(systemName: route.systemImage)
        content.imageProperties.tintColor = route == selectedRoute ? Theme.accentText : Theme.textSecondary
        cell.contentConfiguration = content
        cell.backgroundColor = route == selectedRoute ? Theme.accentContainer : Theme.canvas
        cell.layer.cornerRadius = Theme.cornerSmall
        cell.layer.cornerCurve = .continuous
        cell.accessoryType = route == selectedRoute ? .checkmark : .none
        cell.accessibilityIdentifier = "sidebar-\(route.rawValue)"
        cell.accessibilityTraits = route == selectedRoute ? [.button, .selected] : .button
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let route = AppRoute.primaryRoutes[indexPath.row]
        onSelect?(route)
    }

}
