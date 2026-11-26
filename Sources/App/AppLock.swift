import LocalAuthentication
import UIKit

/// Face ID / device-passcode gate for the app and the private vault.
enum AppLock {

    static let enabledKey = "magdy.appLock.enabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// True only after the current lock screen has been successfully authenticated.
    static private(set) var isUnlocked = false

    static var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Presents an authentication prompt. Device-owner authentication includes
    /// the passcode fallback; unavailable authentication always fails closed.
    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(false)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    /// Gates a presentation: covers the top-most controller first, then authenticates.
    /// Nothing is interactive until the prompt succeeds.
    static func gate(
        viewController: UIViewController,
        reason: String,
        isAppLock: Bool = false,
        onUnlocked: @escaping () -> Void
    ) {
        let presentGate = {
            let presenter = topMostController(startingAt: viewController)
            isUnlocked = false

            // The app lock and vault lock can request the same gate while the app
            // is returning from the background. Share one prompt and both handlers.
            if let locked = presenter as? LockedViewController {
                locked.usesAppLockAuthentication = true
                locked.allowsCancellation = !isAppLock
                locked.authenticationReason = reason
                locked.addUnlockHandler(onUnlocked)
                return
            }

            let locked = LockedViewController()
            locked.modalPresentationStyle = .overFullScreen
            locked.usesAppLockAuthentication = true
            locked.allowsCancellation = !isAppLock
            locked.authenticationReason = reason
            presenter.present(locked, animated: false)
            locked.addUnlockHandler(onUnlocked)
        }

        if Thread.isMainThread {
            presentGate()
        } else {
            DispatchQueue.main.async(execute: presentGate)
        }
    }

    fileprivate static func completeUnlock(locked: LockedViewController, completion: (() -> Void)?) {
        guard locked.presentingViewController != nil, !locked.isBeingDismissed else { return }
        isUnlocked = true
        locked.dismiss(animated: false) { completion?() }
    }

    private static func topMostController(startingAt controller: UIViewController) -> UIViewController {
        var top = controller.view.window?.rootViewController ?? controller
        var visited = Set<ObjectIdentifier>()
        while visited.insert(ObjectIdentifier(top)).inserted {
            if let presented = top.presentedViewController, !presented.isBeingDismissed {
                top = presented
            } else if let navigation = top as? UINavigationController,
                      let visible = navigation.visibleViewController, visible !== top {
                top = visible
            } else if let tabBar = top as? UITabBarController,
                      let selected = tabBar.selectedViewController, selected !== top {
                top = selected
            } else if let split = top as? UISplitViewController,
                      let detail = split.viewControllers.last, detail !== top {
                top = detail
            } else {
                break
            }
        }
        return top
    }
}

/// Full-screen cover shown while the app or private vault is locked.
final class LockedViewController: UIViewController {
    var retry: (() -> Void)?
    fileprivate var usesAppLockAuthentication = false
    var allowsCancellation = false {
        didSet { cancelButton.isHidden = !allowsCancellation }
    }
    private var onUnlocked: (() -> Void)?
    fileprivate var authenticationReason = "Unlock Magdy Browser"
    private var isAuthenticating = false

    private let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
    private let unlockButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        icon.tintColor = Theme.primary
        icon.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        unlockButton.setTitle("Unlock", for: .normal)
        unlockButton.titleLabel?.font = Theme.headline(17)
        unlockButton.tintColor = Theme.primary
        unlockButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        unlockButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(unlockButton)

        cancelButton.setTitle(L.t("cancel"), for: .normal)
        cancelButton.titleLabel?.font = Theme.body(15)
        cancelButton.tintColor = Theme.textSecondary
        cancelButton.isHidden = !allowsCancellation
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            unlockButton.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 24),
            unlockButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.topAnchor.constraint(equalTo: unlockButton.bottomAnchor, constant: 8),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    fileprivate func addUnlockHandler(_ handler: @escaping () -> Void) {
        if let existing = onUnlocked {
            onUnlocked = { existing(); handler() }
        } else {
            onUnlocked = handler
        }
        if !isAuthenticating {
            beginAuthentication()
        }
    }

    private func beginAuthentication() {
        unlockButton.isEnabled = true
        unlockButton.setTitle("Unlock", for: .normal)
        cancelButton.isHidden = !allowsCancellation
        guard AppLock.canAuthenticate else {
            unlockButton.setTitle("Set a device passcode in Settings", for: .normal)
            unlockButton.isEnabled = false
            retry = nil
            return
        }
        guard onUnlocked != nil, !isAuthenticating else { return }
        isAuthenticating = true
        AppLock.authenticate(reason: authenticationReason) { [weak self] success in
            guard let self else { return }
            self.isAuthenticating = false
            guard self.presentingViewController != nil, !self.isBeingDismissed else {
                self.onUnlocked = nil
                return
            }
            if success {
                let handler = self.onUnlocked
                self.onUnlocked = nil
                self.retry = nil
                if self.usesAppLockAuthentication {
                    AppLock.completeUnlock(locked: self, completion: handler)
                } else {
                    handler?()
                }
            } else {
                self.retry = { [weak self] in self?.beginAuthentication() }
            }
        }
    }

    @objc private func retryTapped() { retry?() }

    @objc private func cancelTapped() {
        guard allowsCancellation else { return }
        onUnlocked = nil
        retry = nil
        dismiss(animated: true)
    }
}
