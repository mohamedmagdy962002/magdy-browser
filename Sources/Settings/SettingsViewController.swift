import UIKit
import WebKit

final class SettingsViewController: UITableViewController {

    private enum Row {
        case blockAds, blockTrackers, defaultPrivate, clearData, clearCache, about
    }

    private let sections: [(title: String, rows: [Row])] = [
        ("Privacy", [.blockAds, .blockTrackers, .defaultPrivate, .clearData]),
        ("Storage", [.clearCache]),
        ("About", [.about])
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.detailTextLabel?.text = nil

        switch sections[indexPath.section].rows[indexPath.row] {
        case .blockAds:
            cell.textLabel?.text = "Block ads and popups"
            cell.accessoryView = makeSwitch(key: UserDefaultsKey.blockAds, default: true)
        case .blockTrackers:
            cell.textLabel?.text = "Block trackers"
            cell.accessoryView = makeSwitch(key: UserDefaultsKey.blockTrackers, default: true)
        case .defaultPrivate:
            cell.textLabel?.text = "Open new tabs in Private Mode"
            cell.accessoryView = makeSwitch(key: UserDefaultsKey.defaultPrivate, default: false)
        case .clearData:
            cell.textLabel?.text = "Clear browsing data"
            cell.accessoryType = .disclosureIndicator
        case .clearCache:
            cell.textLabel?.text = "Clear cache"
            cell.accessoryType = .disclosureIndicator
        case .about:
            cell.textLabel?.text = "Magdy Browser 1.0"
            cell.textLabel?.textColor = .secondaryLabel
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].rows[indexPath.row] {
        case .clearData:
            clearBrowsingData()
        case .clearCache:
            clearCache()
        default:
            break
        }
    }

    // MARK: - Actions

    private func makeSwitch(key: String, default defaultValue: Bool) -> UISwitch {
        let control = UISwitch()
        control.isOn = UserDefaultsKey.bool(key, default: defaultValue)
        control.accessibilityIdentifier = key
        control.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
        return control
    }

    @objc private func switchChanged(_ sender: UISwitch) {
        guard let key = sender.accessibilityIdentifier else { return }
        UserDefaults.standard.set(sender.isOn, forKey: key)
        guard key != UserDefaultsKey.defaultPrivate else { return }

        // Filter lists are compiled into the web view configuration, so blocking
        // changes apply to tabs opened after the switch.
        let alert = UIAlertController(
            title: "Applies to new tabs",
            message: "Blocking changes apply the next time you open a new tab.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func clearBrowsingData() {
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases
        ]
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            let alert = UIAlertController(
                title: "Done",
                message: "Cache, cookies and site data cleared.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
    }

    private func clearCache() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
            modifiedSince: .distantPast
        ) { [weak self] in
            let alert = UIAlertController(
                title: "Done",
                message: "Cache cleared.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }
    }
}
