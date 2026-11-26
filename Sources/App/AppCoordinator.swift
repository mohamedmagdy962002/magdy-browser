import UIKit

final class AppCoordinator {
    private(set) var selectedRoute: AppRoute = .browser

    private let browser = BrowserViewController()
    private let library = LibraryViewController()
    private let tools = MediaToolsViewController()
    private let more = MoreViewController()
    private let downloads = DownloadsViewController()
    private let favorites = FavoritesViewController()
    private let history = HistoryViewController()
    private let settings = SettingsViewController()

    private weak var activeContainer: UIViewController?
    private var pendingDownloads: [(url: URL, completion: (() -> Void)?)] = []
    private var isHandlingDownload = false

    private lazy var browserNavigation = makeNavigation(root: browser, route: .browser)
    private lazy var libraryNavigation = makeNavigation(root: library, route: .library)
    private lazy var toolsNavigation = makeNavigation(root: tools, route: .tools)
    private lazy var moreNavigation = makeNavigation(root: more, route: .more)
    private lazy var sidebar = makeSidebar()
    private lazy var sidebarNavigation: UINavigationController = {
        let navigation = UINavigationController(rootViewController: sidebar)
        navigation.view.accessibilityIdentifier = "sidebar-navigation"
        return navigation
    }()
    private lazy var splitPlaceholder = UINavigationController(rootViewController: UIViewController())

    private func makeNavigation(root: UIViewController, route: AppRoute) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: root)
        navigation.tabBarItem = UITabBarItem(
            title: route.title,
            image: UIImage(systemName: route.systemImage),
            tag: AppRoute.primaryRoutes.firstIndex(of: route) ?? 0
        )
        navigation.view.backgroundColor = Theme.canvas
        navigation.view.accessibilityIdentifier = "\(route.rawValue)-navigation"
        return navigation
    }

    private func makeSidebar() -> SidebarViewController {
        let controller = SidebarViewController()
        controller.onSelect = { [weak self] route in
            self?.selectPrimary(route)
        }
        return controller
    }

    func makeCompactController() -> UITabBarController {
        let controller = UITabBarController()
        controller.view.accessibilityIdentifier = "app-tab-bar"
        controller.tabBar.accessibilityIdentifier = "app-tab-bar"
        return controller
    }

    func makeSplitController() -> UISplitViewController {
        let controller = UISplitViewController()
        controller.view.accessibilityIdentifier = "app-split-view"
        controller.preferredDisplayMode = .oneBesideSecondary
        controller.preferredPrimaryColumnWidth = 260
        controller.minimumPrimaryColumnWidth = 220
        controller.maximumPrimaryColumnWidth = 300
        return controller
    }

    func activate(_ container: UIViewController) {
        activeContainer = container
        if let tabs = container as? UITabBarController {
            tabs.viewControllers = AppRoute.primaryRoutes.map(navigation(for:))
            tabs.selectedViewController = navigation(for: selectedRoute)
            tabs.view.accessibilityIdentifier = "app-tab-bar"
        } else if let split = container as? UISplitViewController {
            split.viewControllers = [sidebarNavigation, navigation(for: selectedRoute)]
        }
        sidebar.setSelectedRoute(selectedRoute)
    }

    func deactivate(_ container: UIViewController) {
        if activeContainer === container { activeContainer = nil }
        if let tabs = container as? UITabBarController {
            tabs.viewControllers = []
            tabs.selectedViewController = nil
        } else if let split = container as? UISplitViewController {
            split.viewControllers = [sidebarNavigation, splitPlaceholder]
        }
    }

    func selectPrimary(_ route: AppRoute) {
        guard route.isPrimary else { return }
        selectedRoute = route
        sidebar.setSelectedRoute(route)
        if let tabs = activeContainer as? UITabBarController {
            tabs.selectedViewController = navigation(for: route)
        } else if let split = activeContainer as? UISplitViewController {
            split.viewControllers = [sidebarNavigation, navigation(for: route)]
        }
    }

    func navigate(to route: AppRoute) {
        let navigation = navigation(for: route.hub)
        switch route {
        case .downloads:
            present(downloads, in: navigation)
        case .favorites:
            present(favorites, in: navigation)
        case .history:
            present(history, in: navigation)
        case .settings:
            if navigation.topViewController !== settings {
                present(settings, in: navigation)
            }
        default:
            break
        }
        selectPrimary(route.hub)
    }

    private func present(_ destination: UIViewController, in navigation: UINavigationController) {
        if navigation.topViewController === destination { return }
        if navigation.viewControllers.contains(where: { $0 === destination }) {
            navigation.popToViewController(destination, animated: false)
        } else {
            navigation.popToRootViewController(animated: false)
            navigation.pushViewController(destination, animated: false)
        }
    }

    func openWebURL(_ url: URL, completion: (() -> Void)?) {
        guard url.isWebURL else {
            completion?()
            return
        }
        selectPrimary(.browser)
        browser.loadViewIfNeeded()
        browser.open(url: url, privateMode: false, completion: completion)
    }

    func downloadURL(_ url: URL, from _: UIViewController, completion: (() -> Void)?) {
        pendingDownloads.append((url, completion))
        guard !isHandlingDownload else { return }
        isHandlingDownload = true
        sendNextDownload()
    }

    private func sendNextDownload() {
        guard !pendingDownloads.isEmpty else {
            isHandlingDownload = false
            return
        }
        let request = pendingDownloads.removeFirst()
        selectPrimary(.browser)
        browser.loadViewIfNeeded()
        browser.handleIncomingDownload(request.url) { [weak self] in
            request.completion?()
            self?.sendNextDownload()
        }
    }

    func primaryRoute(for navigation: UINavigationController?) -> AppRoute? {
        switch navigation {
        case browserNavigation: return .browser
        case libraryNavigation: return .library
        case toolsNavigation: return .tools
        case moreNavigation: return .more
        default: return nil
        }
    }

    func refreshLocalizedTitles() {
        for route in AppRoute.primaryRoutes {
            navigation(for: route).tabBarItem.title = route.title
        }
        library.title = L.t("library")
        downloads.title = L.t("downloads")
        favorites.title = L.t("favorites")
        history.title = L.t("history")
        tools.title = L.t("tools")
        more.title = L.t("more")
        settings.title = L.t("settings")
        library.refreshLocalizedContent()
        more.refreshLocalizedContent()
        sidebar.reloadData()
    }

    private func navigation(for route: AppRoute) -> UINavigationController {
        switch route {
        case .browser: return browserNavigation
        case .library, .downloads, .favorites, .history: return libraryNavigation
        case .tools: return toolsNavigation
        case .more, .settings: return moreNavigation
        }
    }

}
