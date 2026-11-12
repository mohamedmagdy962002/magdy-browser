import UIKit
import WebKit

/// In-page search, like Safari's find bar.
final class FindInPageController: UIViewController {

    private let webView: WKWebView
    private let field = UITextField()
    private let countLabel = UILabel()
    private var matches: [WKFindResult] = []
    private var currentIndex = 0

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground

        field.placeholder = L.t("find_in_page")
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)

        countLabel.text = "0"
        countLabel.font = .systemFont(ofSize: 15)
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .center
        countLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let previous = makeButton(systemName: "chevron.up", action: #selector(findPrevious))
        let next = makeButton(systemName: "chevron.down", action: #selector(findNext))
        let done = makeButton(systemName: "xmark.circle.fill", action: #selector(closeTapped))

        let stack = UIStackView(arrangedSubviews: [field, countLabel, previous, next, done])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        ])

        field.becomeFirstResponder()
    }

    private func makeButton(systemName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    @objc private func textChanged() {
        runFind()
    }

    private func runFind() {
        let query = field.text ?? ""
        guard !query.isEmpty else {
            matches = []
            countLabel.text = "0"
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = false
        configuration.caseSensitive = false
        configuration.wraps = true

        webView.findString(query, configuration: configuration) { [weak self] result in
            guard let self else { return }
            switch result {
            case .found(let match):
                self.matches.append(match)
                self.currentIndex = self.matches.count - 1
                self.countLabel.text = "\(self.currentIndex + 1)/\(self.matches.count)"
            case .completed:
                self.countLabel.text = self.matches.isEmpty ? "0" : "\(self.currentIndex + 1)/\(self.matches.count)"
            case .failed:
                self.countLabel.text = "0"
            }
        }
    }

    @objc private func findNext() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        if let match = matches[currentIndex] {
            webView.scrollRangeToVisible(match.range)
        }
        countLabel.text = "\(currentIndex + 1)/\(matches.count)"
    }

    @objc private func findPrevious() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        if let match = matches[currentIndex] {
            webView.scrollRangeToVisible(match.range)
        }
        countLabel.text = "\(currentIndex + 1)/\(matches.count)"
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

extension FindInPageController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        runFind()
        return false
    }
}
