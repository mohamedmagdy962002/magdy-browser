import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var lockCover: UIView?
    private var pendingOpenURL: URL?
    private var pendingDownloadURL: URL?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        resetUITestStateIfNeeded()

        Theme.applyGlobalAppearance()
        ContentBlocker.shared.load()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window

        NotificationCenter.default.addObserver(
            self, selector: #selector(lockRequested), name: .magdyLockRequested, object: nil
        )

        if AppLock.isEnabled {
            lockApp()
        }
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        if AppLock.isEnabled {
            showLockCover()
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        guard AppLock.isEnabled, !isLockScreenPresented else { return }
        lockApp()
    }

    @objc private func lockRequested() {
        lockApp()
    }

    private func lockApp() {
        guard AppLock.isEnabled, let window else {
            removeLockCover()
            return
        }
        showLockCover()
        guard let presenter = topMostViewController(from: window.rootViewController) ?? window.rootViewController else { return }
        AppLock.gate(viewController: presenter, reason: "Unlock Magdy Browser", isAppLock: true) { [weak self] in
            self?.removeLockCover()
            self?.dispatchPendingIntents()
        }
    }

    private var isLockScreenPresented: Bool {
        guard let root = window?.rootViewController else { return false }
        var top = root
        while let presented = top.presentedViewController {
            if presented is LockedViewController { return true }
            top = presented
        }
        return false
    }

    private func topMostViewController(from root: UIViewController?) -> UIViewController? {
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        if let navigation = top as? UINavigationController {
            return navigation.topViewController ?? top
        }
        return top
    }

    private func showLockCover() {
        guard let window, lockCover == nil else { return }
        let cover = UIView(frame: window.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = Theme.canvas
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = Theme.primary
        indicator.startAnimating()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: cover.centerYAnchor)
        ])
        window.addSubview(cover)
        lockCover = cover
    }

    private func removeLockCover() {
        lockCover?.removeFromSuperview()
        lockCover = nil
    }

    private func dispatchPendingIntents() {
        let download = pendingDownloadURL
        let open = pendingOpenURL
        pendingDownloadURL = nil
        pendingOpenURL = nil
        if let download {
            NotificationCenter.default.post(name: .magdyDownloadURL, object: download)
        }
        if let open {
            NotificationCenter.default.post(name: .magdyOpenURL, object: open)
        }
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let host = url.host?.lowercased()
        guard url.scheme?.lowercased() == "magdy", host == "open" || host == "download" else { return false }
        if let source = options[.sourceApplication] as? String,
           source != "com.magdy.browser.share", source != "com.magdy.browser.action" {
            return false
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let target = components?.queryItems?.first(where: { $0.name == "url" })?.value
        let search = components?.queryItems?.first(where: { $0.name == "q" })?.value
        let webDestination = target.flatMap(URL.webURL(from:))
        let searchDestination = search.flatMap { SearchEngine.effectiveSearchURL(for: $0) }
        guard let resolved = host == "download" ? webDestination : (webDestination ?? searchDestination) else {
            return false
        }

        if AppLock.isEnabled && !AppLock.isUnlocked {
            if host == "download" {
                pendingDownloadURL = resolved
            } else {
                pendingOpenURL = resolved
            }
            lockApp()
            return true
        }

        DispatchQueue.main.async {
            if host == "download" {
                NotificationCenter.default.post(name: .magdyDownloadURL, object: resolved)
            } else {
                NotificationCenter.default.post(name: .magdyOpenURL, object: resolved)
            }
        }
        return true
    }

    private func resetUITestStateIfNeeded() {
        guard ProcessInfo.processInfo.environment["MAGDY_UI_TEST"] == "1" else { return }
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.searchSuggestions)
        UserDefaults.standard.set(false, forKey: "magdy.memorySaver")
        UserDefaults.standard.set("light", forKey: "magdy.theme")
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in ["current-wallpaper.png", "current-wallpaper.jpg"] {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
    }
}
