import UIKit

final class RootViewController: UITabBarController {
    private var themeObserver: NSObjectProtocol?
    private var languageObserver: NSObjectProtocol?

    deinit {
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = Theme.forcedStyle
        view.accessibilityIdentifier = "root-tabs"
        view.semanticContentAttribute = L.isRightToLeft ? .forceRightToLeft : .forceLeftToRight

        themeObserver = NotificationCenter.default.addObserver(
            forName: .magdyThemeChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.overrideUserInterfaceStyle = Theme.forcedStyle
        }
        languageObserver = NotificationCenter.default.addObserver(
            forName: .magdyLanguageChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.view.semanticContentAttribute = L.isRightToLeft ? .forceRightToLeft : .forceLeftToRight
            let keys = ["browser", "downloads", "media", "favorites", "history", "settings"]
            for (index, controller) in (self.viewControllers ?? []).enumerated() where index < keys.count {
                controller.tabBarItem.title = L.t(keys[index])
            }
        }

        let browser = UINavigationController(rootViewController: BrowserViewController())
        browser.tabBarItem = UITabBarItem(
            title: "Browser", image: UIImage(systemName: "globe"), tag: 0
        )

        let downloads = UINavigationController(rootViewController: DownloadsViewController())
        downloads.tabBarItem = UITabBarItem(
            title: "Downloads", image: UIImage(systemName: "arrow.down.circle"), tag: 1
        )

        let media = UINavigationController(rootViewController: MediaToolsViewController())
        media.tabBarItem = UITabBarItem(
            title: "Media", image: UIImage(systemName: "wand.and.stars"), tag: 2
        )

        let favorites = UINavigationController(rootViewController: FavoritesViewController())
        favorites.tabBarItem = UITabBarItem(
            title: "Favorites", image: UIImage(systemName: "star"), tag: 3
        )

        let history = UINavigationController(rootViewController: HistoryViewController())
        history.tabBarItem = UITabBarItem(
            title: L.t("history"), image: UIImage(systemName: "clock.arrow.circlepath"), tag: 4
        )

        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(
            title: L.t("settings"), image: UIImage(systemName: "gearshape"), tag: 5
        )

        viewControllers = [browser, downloads, media, favorites, history, settings]
    }
}
