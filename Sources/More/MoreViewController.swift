import UIKit

final class MoreViewController: UITableViewController {
    private enum Item: CaseIterable {
        case settings, about

        var title: String {
            switch self {
            case .settings: return L.t("settings")
            case .about: return L.t("about")
            }
        }

        var image: String {
            switch self {
            case .settings: return AppRoute.settings.systemImage
            case .about: return "info.circle"
            }
        }
    }

    private weak var footerLabel: UILabel?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.t("more")
        view.accessibilityIdentifier = "more-screen"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 56
        navigationController?.navigationBar.prefersLargeTitles = true
        buildFooter()
    }

    func refreshLocalizedContent() {
        guard isViewLoaded else { return }
        footerLabel?.text = L.t("unlimited_note")
        tableView.reloadData()
        view.setNeedsLayout()
    }

    private func buildFooter() {
        let label = UILabel()
        label.text = L.t("unlimited_note")
        label.font = Theme.footnote
        label.textColor = Theme.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        footerLabel = label

        let footer = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 96))
        footer.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: footer.topAnchor, constant: 24),
            label.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -24),
            label.bottomAnchor.constraint(lessThanOrEqualTo: footer.bottomAnchor, constant: -16)
        ])
        tableView.tableFooterView = footer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let label = footerLabel, let footer = tableView.tableFooterView else { return }
        let width = max(1, tableView.bounds.width - 48)
        let height = ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height) + 40
        if abs(footer.frame.height - height) > 1 {
            footer.frame.size.height = height
            tableView.tableFooterView = footer
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Item.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = Item.allCases[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = item.title
        content.textProperties.font = Theme.headline(17, weight: .semibold)
        content.image = UIImage(systemName: item.image)
        content.imageProperties.tintColor = Theme.accentText
        cell.contentConfiguration = content
        cell.backgroundColor = Theme.card
        cell.layer.cornerRadius = Theme.corner
        cell.layer.cornerCurve = .continuous
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "more-\(item)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Item.allCases[indexPath.row] {
        case .settings:
            appRouteHandler?.navigate(to: .settings)
        case .about:
            presentAbout()
        }
    }

    private func presentAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let alert = UIAlertController(
            title: "Magdy \(version) (\(build))",
            message: "\(L.t("unlimited_note"))\n\n\(L.t("local_data_note"))",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = view.bounds
        }
        present(alert, animated: true)
    }

}
