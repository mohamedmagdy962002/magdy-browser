import UIKit
import UniformTypeIdentifiers

/// "Open in Magdy" — hands a shared URL to the browser.
final class ShareViewController: UIViewController {

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

        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            ? UTType.url.identifier
            : UTType.plainText.identifier

        provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] value, _ in
            var text = ""
            if let url = value as? URL {
                text = url.absoluteString
            } else if let string = value as? String {
                text = string
            }
            DispatchQueue.main.async {
                self?.open(text)
            }
        }
    }

    private func open(_ text: String) {
        guard !text.isEmpty,
              let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "magdy://open?url=\(encoded)") else {
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
