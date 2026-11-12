import UIKit
import WebKit

final class SettingsViewController: UITableViewController {

    private enum Row {
        case blockAds, blockTrackers, strongBlocking, defaultPrivate, clearData, clearCache
        case filterLists, wallpaper, language, about
    }

    private let sections: [(title: String, rows: [Row])] = [
        (L.t("block_ads"), [.blockAds, .blockTrackers, .strongBlocking]),
        (L.t("history"), [.defaultPrivate, .clearData]),
        (L.t("clear_cache"), [.clearCache]),
        (L.t("language"), [.language, .filterLists, .wallpaper]),
        (L.t("about"), [.about])
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.t("settings")
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
        cell.textLabel?.textColor = .label

        switch sections[indexPath.section].rows[indexPath.row] {
        case .blockAds:
            cell.textLabel?.text = L.t("block_ads")
            cell.accessoryView = makeSwitch(key: UserDefaultsKey.blockAds, default: true)
        case .blockTrackers:
            cell.textLabel?.text = L.t("block_trackers")
            cell.accessoryView = makeSwitch(key: UserDefaultsKey.blockTrackers, default: true)
        case .strongBlocking:
            cell.textLabel?.text = "Extended blocking (86k rules)"
            cell.accessoryView = makeSwitch(key: UserDefaultsKey.strongBlocking, default: true)
        case .defaultPrivate:
            cell.textLabel?.text = L.t("default_private")
            cell.accessoryView = makeSwitch(key: UserDefaultsKey.defaultPrivate, default: false)
        case .clearData:
            cell.textLabel?.text = L.t("clear_data")
            cell.accessoryType = .disclosureIndicator
        case .clearCache:
            cell.textLabel?.text = L.t("clear_cache")
            cell.accessoryType = .disclosureIndicator
        case .language:
            cell.textLabel?.text = L.t("language")
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = L.resolvedLanguage.uppercased()
        case .filterLists:
            cell.textLabel?.text = "Filter Lists"
            cell.accessoryType = .disclosureIndicator
        case .wallpaper:
            cell.textLabel?.text = "Wallpaper"
            cell.accessoryType = .disclosureIndicator
        case .about:
            cell.textLabel?.text = L.t("about")
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
        case .language:
            chooseLanguage()
        case .filterLists:
            navigationController?.pushViewController(FilterListsViewController(), animated: true)
        case .wallpaper:
            let picker = WallpaperPickerViewController()
            let navigation = UINavigationController(rootViewController: picker)
            navigation.modalPresentationStyle = .pageSheet
            present(navigation, animated: true)
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
        guard key == UserDefaultsKey.blockAds || key == UserDefaultsKey.blockTrackers else { return }

        // Filter lists are compiled into the web view configuration, so blocking
        // changes apply to tabs opened after the switch.
        let alert = UIAlertController(
            title: "Applies to new tabs",
            message: "Blocking changes apply the next time you open a new tab.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
        present(alert, animated: true)
    }

    private func chooseLanguage() {
        let options = [("system", "System"), ("en", "English"), ("ar", "العربية"), ("fr", "Français"), ("es", "Español"), ("de", "Deutsch"), ("tr", "Türkçe")]
        let sheet = UIAlertController(title: L.t("language"), message: nil, preferredStyle: .actionSheet)
        for (code, name) in options {
            sheet.addAction(UIAlertAction(title: name, style: .default) { _ in
                UserDefaults.standard.set(code, forKey: UserDefaultsKey.language)
                self.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: L.t("cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = tableView.cellForRow(at: IndexPath(row: 0, section: 3))
        }
        present(sheet, animated: true)
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
            HistoryStore.shared.clear()
            self?.showAlert(title: L.t("done"), message: "Cache, cookies, site data and history cleared.")
        }
    }

    private func clearCache() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache],
            modifiedSince: .distantPast
        ) { [weak self] in
            self?.showAlert(title: L.t("done"), message: "Cache cleared.")
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
        present(alert, animated: true)
    }
}
