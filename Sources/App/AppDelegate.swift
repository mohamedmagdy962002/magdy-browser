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
        ContentBlocker.shared.load()

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
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
            let destination = URL(string: "https://duckduckgo.com/?q=\(search)")
            if let destination {
                NotificationCenter.default.post(name: .magdyOpenURL, object: destination)
                return true
            }
        }
        return false
    }
}
