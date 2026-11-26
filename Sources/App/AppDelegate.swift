import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var lockCover: UIView?
    private var pendingIntents: [PendingIntent] = []
    private var isDispatchingIntent = false

    private enum PendingIntent {
        case open(URL)
        case download(URL)
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        resetUITestStateIfNeeded()

        Theme.applyGlobalAppearance()
        ContentBlocker.shared.load()

        let window = UIWindow(frame: UIScreen.main.bounds)
        let root = RootViewController()
        root.prepareForLaunch()
        window.rootViewController = root
        self.window = window
        window.makeKeyAndVisible()

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
        guard AppLock.isEnabled else { return }
        lockApp()
    }

    @objc private func lockRequested() {
        lockApp()
    }

    private func lockApp() {
        guard AppLock.isEnabled else {
            removeLockCover()
            return
        }
        guard let window else { return }
        showLockCover()
        guard let root = window.rootViewController else { return }
        AppLock.gate(viewController: root, reason: "Unlock Magdy Browser", isAppLock: true) { [weak self] in
            self?.removeLockCover()
            self?.dispatchPendingIntents()
        }
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
        guard !isDispatchingIntent else { return }
        dispatchNextIntent()
    }

    private func dispatchNextIntent() {
        guard !pendingIntents.isEmpty else {
            isDispatchingIntent = false
            return
        }
        isDispatchingIntent = true
        let intent = pendingIntents.removeFirst()
        dispatch(intent) { [weak self] in
            DispatchQueue.main.async {
                self?.dispatchNextIntent()
            }
        }
    }

    private func dispatch(_ intent: PendingIntent, completion: @escaping () -> Void) {
        guard let handler = window?.rootViewController as? AppRouteHandler else {
            completion()
            return
        }
        switch intent {
        case .open(let url): handler.openWebURL(url, completion: completion)
        case .download(let url): handler.downloadURL(url, completion: completion)
        }
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let host = url.host?.lowercased()
        guard url.scheme?.lowercased() == "magdy", host == "open" || host == "download" else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let target = components?.queryItems?.first(where: { $0.name == "url" })?.value
        let search = components?.queryItems?.first(where: { $0.name == "q" })?.value
        if host == "open", target == nil, search == nil {
            return true
        }
        if let source = options[.sourceApplication] as? String,
           source != "com.magdy.browser.share", source != "com.magdy.browser.action" {
            return false
        }
        let webDestination = target.flatMap(URL.webURL(from:))
        let searchDestination = search.flatMap { SearchEngine.effectiveSearchURL(for: $0) }
        guard let resolved = host == "download" ? webDestination : (webDestination ?? searchDestination) else {
            return false
        }

        let intent: PendingIntent = host == "download" ? .download(resolved) : .open(resolved)
        if AppLock.isEnabled && !AppLock.isUnlocked {
            pendingIntents.append(intent)
            lockApp()
            return true
        }

        DispatchQueue.main.async {
            self.pendingIntents.append(intent)
            self.dispatchPendingIntents()
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
        UserDefaults.standard.set("en", forKey: UserDefaultsKey.language)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in ["current-wallpaper.png", "current-wallpaper.jpg"] {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
    }
}
