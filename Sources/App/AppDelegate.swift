import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if L.isRightToLeft {
            UIView.appearance().semanticContentAttribute = .forceRightToLeft
        }
        Theme.applyGlobalAppearance()
        ContentBlocker.shared.load()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window

        // App lock on launch — cover first, then Face ID.
        if AppLock.isEnabled {
            lockApp()
        }
        return true
    }

    /// Re-locks every time the app returns from the background.
    func applicationWillEnterForeground(_ application: UIApplication) {
        guard AppLock.isEnabled,
              window?.rootViewController?.presentedViewController is LockedViewController == false else { return }
        lockApp()
    }

    private func lockApp() {
        guard let root = window?.rootViewController else { return }
        AppLock.gate(viewController: root, reason: "Unlock Magdy Browser", onUnlocked: {})
    }

    /// Handles magdy://open?url=... from the share / action extensions.
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard url.scheme == "magdy" else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let target = components?.queryItems?.first(where: { $0.name == "url" })?.value
        let search = components?.queryItems?.first(where: { $0.name == "q" })?.value

        if url.host == "download", let target, let destination = URL(string: target) {
            NotificationCenter.default.post(name: .magdyDownloadURL, object: destination)
            return true
        }
        if let target, let destination = URL(string: target) {
            NotificationCenter.default.post(name: .magdyOpenURL, object: destination)
            return true
        }
        if let search, !search.isEmpty {
            let destination = SearchEngine.selected.searchURL(for: search)
            if let destination {
                NotificationCenter.default.post(name: .magdyOpenURL, object: destination)
                return true
            }
        }
        return false
    }
}
