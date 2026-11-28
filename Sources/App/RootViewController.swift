import UIKit

final class RootViewController: UIViewController {
    private(set) lazy var coordinator = AppCoordinator()
    private var activeContainer: UIViewController?
    private var compactController: UITabBarController?
    private var splitController: UISplitViewController?
    private var needsShellUpdate = false
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

    func prepareForLaunch() {
        _ = coordinator
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = Theme.forcedStyle
        view.backgroundColor = Theme.canvas
        view.accessibilityIdentifier = "app-root"
        updateSemanticContentAttribute()

        themeObserver = NotificationCenter.default.addObserver(
            forName: .magdyThemeChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.overrideUserInterfaceStyle = Theme.forcedStyle
        }
        languageObserver = NotificationCenter.default.addObserver(
            forName: .magdyLanguageChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateSemanticContentAttribute()
            self?.coordinator.refreshLocalizedTitles()
        }

        updateShell()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            requestShellUpdate()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if needsShellUpdate, let activeContainer, !hasPresentedController(in: activeContainer) {
            needsShellUpdate = false
            updateShell()
        }
    }

    private func requestShellUpdate() {
        if let activeContainer, hasPresentedController(in: activeContainer) {
            needsShellUpdate = true
        } else {
            updateShell()
        }
    }

    private func hasPresentedController(in controller: UIViewController) -> Bool {
        if controller.presentedViewController != nil { return true }
        return controller.children.contains(where: hasPresentedController(in:))
    }

    private func updateSemanticContentAttribute() {
        view.semanticContentAttribute = L.isRightToLeft ? .forceRightToLeft : .forceLeftToRight
    }

    private func updateShell() {
        let container: UIViewController
        if traitCollection.horizontalSizeClass == .regular {
            if splitController == nil {
                let split = coordinator.makeSplitController()
                split.delegate = self
                splitController = split
            }
            container = splitController!
        } else {
            if compactController == nil {
                let tabs = coordinator.makeCompactController()
                tabs.delegate = self
                compactController = tabs
            }
            container = compactController!
        }

        guard container !== activeContainer else { return }
        if let outgoing = activeContainer {
            outgoing.willMove(toParent: nil)
            outgoing.view.removeFromSuperview()
            outgoing.removeFromParent()
            coordinator.deactivate(outgoing)
        }

        addChild(container)
        container.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container.view)
        NSLayoutConstraint.activate([
            container.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        coordinator.activate(container)
        container.didMove(toParent: self)
        activeContainer = container
    }
}

extension RootViewController: AppRouteHandler {
    func navigate(to route: AppRoute) {
        coordinator.navigate(to: route)
    }

    func openWebURL(_ url: URL, completion: (() -> Void)?) {
        coordinator.openWebURL(url, completion: completion)
    }

    func downloadURL(_ url: URL, completion: (() -> Void)?) {
        coordinator.downloadURL(url, from: view.window?.rootViewController ?? self, completion: completion)
    }
}

extension RootViewController: UITabBarControllerDelegate {
    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        guard let route = coordinator.primaryRoute(for: viewController as? UINavigationController) else { return }
        coordinator.selectPrimary(route)
    }
}

extension RootViewController: UISplitViewControllerDelegate {
    func splitViewController(
        _ splitViewController: UISplitViewController,
        collapseSecondaryViewController secondaryViewController: UIViewController,
        onto primaryViewController: UIViewController
    ) -> Bool {
        true
    }
}
