import UIKit

/// Lets the user switch the shipped filter lists on and off.
final class FilterListsViewController: UITableViewController {

    private let manager = FilterListManager.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Filter Lists"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.backgroundColor = Theme.canvas
        tableView.separatorStyle = .none
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        manager.lists.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let list = manager.lists[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = list.title
        content.textProperties.font = Theme.body(15, weight: .semibold)
        content.secondaryText = "\(list.domains.formatted()) domains · \(ByteCountFormatter.string(fromByteCount: Int64(list.bytes), countStyle: .file))"
        content.secondaryTextProperties.color = Theme.textSecondary
        cell.contentConfiguration = content

        cell.backgroundColor = Theme.card
        cell.layer.cornerRadius = Theme.corner
        cell.layer.cornerCurve = .continuous
        cell.selectionStyle = .none

        let toggle = UISwitch()
        toggle.isOn = manager.enabledIDs.contains(list.id)
        toggle.accessibilityIdentifier = list.id
        toggle.onTintColor = Theme.primary
        toggle.addTarget(self, action: #selector(toggled(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    @objc private func toggled(_ sender: UISwitch) {
        guard let id = sender.accessibilityIdentifier else { return }
        var enabled = manager.enabledIDs
        if sender.isOn {
            enabled.insert(id)
        } else {
            enabled.remove(id)
        }
        manager.enabledIDs = enabled
        manager.compileEnabled()
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Lists are compiled into WebKit rules. Changes apply to new tabs."
    }
}
