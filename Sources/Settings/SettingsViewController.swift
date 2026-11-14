import UIKit
import WebKit

final class SettingsViewController: UITableViewController {

    private enum Row {
        case blockAds, blockTrackers, strongBlocking, defaultPrivate, clearData, clearCache
        case filterLists, customFilterLists, wallpaper, language, about
        case appLock, nightMode, searchEngine, vault, readingList, blockStats, theme, textZoom
    }

    private let sections: [(title: String, rows: [Row])] = [
        (L.t("block_ads"), [.blockAds, .blockTrackers, .strongBlocking, .filterLists, .customFilterLists, .blockStats]),
        ("Privacy", [.defaultPrivate, .clearData, .clearCache, .appLock, .vault]),
        ("Appearance", [.theme, .nightMode, .wallpaper, .textZoom]),
        (L.t("language"), [.language, .searchEngine, .readingList]),
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
        case .customFilterLists:
            cell.textLabel?.text = "Custom Filter Lists"
            cell.accessoryType = .disclosureIndicator
        case .wallpaper:
            cell.textLabel?.text = "Wallpaper"
            cell.accessoryType = .disclosureIndicator
        case .appLock:
            cell.textLabel?.text = "App Lock (Face ID)"
            cell.accessoryView = makeSwitch(key: AppLock.enabledKey, default: false)
        case .theme:
            cell.textLabel?.text = "Theme"
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = (UserDefaults.standard.string(forKey: "magdy.theme") ?? "system").capitalized
        case .textZoom:
            cell.textLabel?.text = "Text Size"
            cell.accessoryType = .disclosureIndicator
            let zoom = UserDefaults.standard.object(forKey: BrowserTab.textZoomKey) as? Double ?? 100
            cell.detailTextLabel?.text = "\(Int(zoom))%"
        case .nightMode:
            cell.textLabel?.text = "Night Mode"
            cell.accessoryView = makeSwitch(key: "magdy.nightMode", default: false)
        case .searchEngine:
            cell.textLabel?.text = "Search Engine"
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = SearchEngine.selected.name
        case .vault:
            cell.textLabel?.text = "Private Vault"
            cell.accessoryType = .disclosureIndicator
        case .readingList:
            cell.textLabel?.text = "Reading List"
            cell.accessoryType = .disclosureIndicator
        case .blockStats:
            cell.textLabel?.text = "Ads blocked"
            cell.detailTextLabel?.text = BlockStats.shared.total.formatted()
            cell.accessoryType = .none
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
            clearBrowsingDataByRange()
        case .clearCache:
            clearCache()
        case .language:
            chooseLanguage()
        case .filterLists:
            navigationController?.pushViewController(FilterListsViewController(), animated: true)
        case .customFilterLists:
            navigationController?.pushViewController(CustomFilterListsViewController(), animated: true)
        case .wallpaper:
            let picker = WallpaperPickerViewController()
            let navigation = UINavigationController(rootViewController: picker)
            navigation.modalPresentationStyle = .pageSheet
            present(navigation, animated: true)
        case .searchEngine:
            chooseSearchEngine()
        case .vault:
            let vault = VaultViewController()
            let navigation = UINavigationController(rootViewController: vault)
            navigation.modalPresentationStyle = .pageSheet
            AppLock.gate(viewController: self, reason: "Unlock your Private Vault") { [weak self] in
                self?.present(navigation, animated: true)
            }
        case .readingList:
            navigationController?.pushViewController(ReadingListViewController(), animated: true)
        case .theme:
            chooseTheme()
        case .textZoom:
            chooseTextZoom()
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
        if key == "magdy.nightMode" {
            NotificationCenter.default.post(name: .magdyNightModeChanged, object: sender.isOn)
        }
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

    private func chooseTheme() {
        let sheet = UIAlertController(title: "Theme", message: nil, preferredStyle: .actionSheet)
        for (label, value) in [("System", "system"), ("Light", "light"), ("Dark", "dark")] {
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                UserDefaults.standard.set(value, forKey: "magdy.theme")
                NotificationCenter.default.post(name: .magdyThemeChanged, object: nil)
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: L.t("cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func chooseTextZoom() {
        let sheet = UIAlertController(title: "Text Size", message: nil, preferredStyle: .actionSheet)
        for percent in [80, 90, 100, 110, 125, 150, 175, 200] {
            sheet.addAction(UIAlertAction(title: "\(percent)%", style: .default) { [weak self] _ in
                UserDefaults.standard.set(Double(percent), forKey: BrowserTab.textZoomKey)
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: L.t("cancel"), style: .cancel))
        present(sheet, animated: true)
    }

    private func chooseSearchEngine() {
        let sheet = UIAlertController(title: "Search Engine", message: nil, preferredStyle: .actionSheet)
        for engine in SearchEngine.allCases {
            sheet.addAction(UIAlertAction(title: engine.name, style: .default) { [weak self] _ in
                SearchEngine.selected = engine
                self?.tableView.reloadData()
            })
        }
        sheet.addAction(UIAlertAction(title: L.t("cancel"), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = tableView.cellForRow(at: IndexPath(row: 0, section: 3))
        }
        present(sheet, animated: true)
    }

    private func clearBrowsingData(since date: Date) {
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases
        ]
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: date) { [weak self] in
            HistoryStore.shared.clear()
            self?.showAlert(title: L.t("done"), message: "Cache, cookies, site data and history cleared.")
        }
    }

    private func clearBrowsingDataByRange() {
        let sheet = UIAlertController(title: "Clear Browsing Data", message: nil, preferredStyle: .actionSheet)
        let ranges: [(String, TimeInterval)] = [
            ("Last hour", -3600),
            ("Last 24 hours", -86400),
            ("Last 7 days", -7 * 86400),
            ("All time", .distantPast.timeIntervalSinceNow)
        ]
        for (title, interval) in ranges {
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.clearBrowsingData(since: Date().addingTimeInterval(interval))
            })
        }
        sheet.addAction(UIAlertAction(title: L.t("cancel"), style: .cancel))
        present(sheet, animated: true)
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
