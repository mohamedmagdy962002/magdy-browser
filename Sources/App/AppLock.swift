import LocalAuthentication
import UIKit

/// Face ID / passcode gate for the app and the private vault.
enum AppLock {

    static let enabledKey = "magdy.appLock.enabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Presents a biometric prompt. Falls back to the device passcode automatically.
    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(true) // No biometrics/passcode set — nothing to gate with.
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    /// Gates a presentation: shows a locked cover until the user authenticates.
    static func gate(viewController: UIViewController, reason: String, onUnlocked: @escaping () -> Void) {
        authenticate(reason: reason) { success in
            if success {
                onUnlocked()
            } else {
                let locked = LockedViewController()
                locked.retry = { gate(viewController: viewController, reason: reason, onUnlocked: onUnlocked) }
                viewController.present(locked, animated: false)
            }
        }
    }
}

/// Full-screen cover shown while the app is locked.
final class LockedViewController: UIViewController {
    var retry: (() -> Void)?

    private let icon = UIImageView(image: UIImage(systemName: "lock.fill"))

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
        let button = UIButton(type: .system)
        button.setTitle("Unlock", for: .normal)
        button.titleLabel?.font = Theme.headline(17)
        button.tintColor = Theme.primary
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 24),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func retryTapped() { retry?() }
}
