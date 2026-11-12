import UIKit
import UniformTypeIdentifiers

/// "Search in Magdy" — action extension that sends shared text to the browser's search.
final class ActionViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractAndOpen()
    }

    private func extractAndOpen() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first else {
            finish()
            return
        }

        let type = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            ? UTType.plainText.identifier
            : UTType.url.identifier

        provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] value, _ in
            var text = ""
            if let string = value as? String {
                text = string
            } else if let url = value as? URL {
                text = url.absoluteString
            }
            DispatchQueue.main.async {
                self?.open(text)
            }
        }
    }

    private func open(_ text: String) {
        guard !text.isEmpty,
              let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "magdy://open?q=\(encoded)") else {
            finish()
            return
        }
        extensionContext?.open(url) { [weak self] _ in
            self?.finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
