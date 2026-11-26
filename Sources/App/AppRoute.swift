import UIKit

enum AppRoute: String, CaseIterable {
    case browser
    case library
    case tools
    case more
    case downloads
    case favorites
    case history
    case settings

    static let primaryRoutes: [AppRoute] = [.browser, .library, .tools, .more]

    var title: String {
        switch self {
        case .browser, .library, .tools, .more, .downloads, .favorites, .history, .settings:
            return L.t(rawValue)
        }
    }

    var systemImage: String {
        switch self {
        case .browser: return "globe"
        case .library: return "rectangle.stack"
        case .tools: return "slider.horizontal.3"
        case .more: return "ellipsis.circle"
        case .downloads: return "arrow.down.circle"
        case .favorites: return "star"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    var hub: AppRoute {
        switch self {
        case .downloads, .favorites, .history: return .library
        case .settings: return .more
        default: return self
        }
    }

    var isPrimary: Bool {
        Self.primaryRoutes.contains(self)
    }
}

protocol AppRouteHandler: AnyObject {
    func navigate(to route: AppRoute)
    func openWebURL(_ url: URL, completion: (() -> Void)?)
    func downloadURL(_ url: URL, completion: (() -> Void)?)
}

extension AppRouteHandler {
    func openWebURL(_ url: URL) {
        openWebURL(url, completion: nil)
    }

    func downloadURL(_ url: URL) {
        downloadURL(url, completion: nil)
    }
}

extension UIViewController {
    var appRouteHandler: AppRouteHandler? {
        var controller: UIViewController? = self
        var visited = Set<ObjectIdentifier>()
        while let current = controller, visited.insert(ObjectIdentifier(current)).inserted {
            if let handler = current as? AppRouteHandler {
                return handler
            }
            controller = current.parent
        }
        return view.window?.rootViewController as? AppRouteHandler
    }
}
