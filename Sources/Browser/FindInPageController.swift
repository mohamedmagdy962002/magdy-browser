import UIKit
import WebKit

/// In-page search, like Safari's find bar. Uses injected JavaScript so it works
/// on every page and highlights every match.
final class FindInPageController: UIViewController {

    private let webView: WKWebView
    private let field = UITextField()
    private let countLabel = UILabel()
    private var matches: [Int] = []
    private var currentIndex = 0
    private var searchGeneration = 0

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
        field.accessibilityIdentifier = "find-field"
        field.borderStyle = .roundedRect
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)

        countLabel.text = "0"
        countLabel.accessibilityIdentifier = "find-count"
        countLabel.font = .systemFont(ofSize: 15)
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .center
        countLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        countLabel.adjustsFontForContentSizeCategory = true

        let previous = makeButton(systemName: "chevron.up", action: #selector(previousMatch))
        let next = makeButton(systemName: "chevron.down", action: #selector(nextMatch))
        let close = makeButton(systemName: "xmark.circle.fill", action: #selector(closeTapped))

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.addArrangedSubview(field)
        stack.addArrangedSubview(countLabel)
        stack.addArrangedSubview(previous)
        stack.addArrangedSubview(next)
        stack.addArrangedSubview(close)
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
        button.accessibilityIdentifier = "find-\(systemName)"
        button.accessibilityLabel = systemName == "chevron.up"
            ? "Previous match"
            : (systemName == "chevron.down" ? "Next match" : "Close find bar")
        button.addTarget(self, action: action, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }

    @objc private func textChanged() {
        runFind()
    }

    // MARK: - Search

    private func runFind() {
        searchGeneration += 1
        let generation = searchGeneration
        let query = field.text ?? ""
        guard !query.isEmpty else {
            matches = []
            countLabel.text = "0"
            clearHighlights()
            return
        }
        let script = FindScript.highlight(query)
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self, self.searchGeneration == generation else { return }
                let count = max(0, (result as? NSNumber)?.intValue ?? 0)
                self.matches = Array(0..<count)
                self.currentIndex = 0
                self.countLabel.text = count == 0 ? "0" : "1/\(count)"
                self.countLabel.accessibilityValue = self.countLabel.text
                if count > 0 {
                    self.scrollToCurrent()
                }
            }
        }
    }

    private func clearHighlights() {
        webView.evaluateJavaScript(FindScript.clear) { _, _ in }
    }

    @objc private func nextMatch() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex + 1) % matches.count
        countLabel.text = "\(currentIndex + 1)/\(matches.count)"
        countLabel.accessibilityValue = countLabel.text
        scrollToCurrent()
    }

    @objc private func previousMatch() {
        guard !matches.isEmpty else { return }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        countLabel.text = "\(currentIndex + 1)/\(matches.count)"
        countLabel.accessibilityValue = countLabel.text
        scrollToCurrent()
    }

    private func scrollToCurrent() {
        let script = FindScript.scrollTo(currentIndex)
        webView.evaluateJavaScript(script) { _, _ in }
    }

    @objc private func closeTapped() {
        searchGeneration += 1
        clearHighlights()
        dismiss(animated: true)
    }
}

extension FindInPageController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        runFind()
        return false
    }
}

/// JavaScript helpers for find-in-page.
enum FindScript {
    static func highlight(_ query: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: query, options: [.fragmentsAllowed]) else {
            return clear
        }
        let escaped = String(decoding: data, as: UTF8.self)
        return """
        (function () {
          if (window.__magdyFindCleanup) { window.__magdyFindCleanup(); }
          const query = \(escaped);
          if (!query) return 0;
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
          const targets = [];
          let node;
          while ((node = walker.nextNode())) {
            const parent = node.parentElement;
            if (!parent) continue;
            const tag = parent.tagName;
            if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') continue;
            if (node.nodeValue && node.nodeValue.toLowerCase().indexOf(query.toLowerCase()) !== -1) {
              targets.push(node);
            }
          }
          const marks = [];
          targets.forEach((textNode) => {
            const text = textNode.nodeValue;
            const lower = text.toLowerCase();
            const needle = query.toLowerCase();
            const fragment = document.createDocumentFragment();
            let cursor = 0;
            let found;
            while ((found = lower.indexOf(needle, cursor)) !== -1) {
              fragment.appendChild(document.createTextNode(text.slice(cursor, found)));
              const mark = document.createElement('mark');
              mark.setAttribute('data-magdy-find', '1');
              mark.style.background = '#ffd60a';
              mark.style.color = '#000';
              mark.textContent = text.slice(found, found + needle.length);
              fragment.appendChild(mark);
              marks.push(mark);
              cursor = found + needle.length;
            }
            fragment.appendChild(document.createTextNode(text.slice(cursor)));
            textNode.parentNode.replaceChild(fragment, textNode);
          });
          window.__magdyFindCleanup = function () {
            marks.forEach((mark) => {
              const parent = mark.parentNode;
              if (!parent) return;
              parent.replaceChild(document.createTextNode(mark.textContent), mark);
              parent.normalize();
            });
            window.__magdyFindCleanup = null;
          };
          return marks.length;
        })();
        """
    }

    static let clear = """
    (function () {
      if (window.__magdyFindCleanup) { window.__magdyFindCleanup(); }
      return true;
    })();
    """

    static func scrollTo(_ index: Int) -> String {
        let behavior = UIAccessibility.isReduceMotionEnabled ? "auto" : "smooth"
        return """
        (function () {
          const marks = document.querySelectorAll('mark[data-magdy-find="1"]');
          marks.forEach(function (mark) {
            mark.style.background = '#ffd60a';
            mark.style.boxShadow = 'none';
          });
          if (marks.length) {
            const current = marks[Math.max(0, Math.min(marks.length - 1, \(index)))];
            current.style.background = '#ff9f0a';
            current.style.boxShadow = '0 0 0 2px rgba(0,0,0,.35)';
            current.scrollIntoView({ behavior: '\(behavior)', block: 'center' });
          }
          return true;
        })();
        """
    }
}
