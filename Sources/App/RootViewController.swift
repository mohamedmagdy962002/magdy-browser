import UIKit

final class RootViewController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

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

        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(
            title: "Settings", image: UIImage(systemName: "gearshape"), tag: 4
        )

        viewControllers = [browser, downloads, media, favorites, settings]
    }
}
