import UIKit
import UniformTypeIdentifiers

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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finish()
            return
        }
        var components = URLComponents()
        components.scheme = "magdy"
        components.host = "open"
        if let destination = URL.webURL(from: trimmed) {
            components.queryItems = [URLQueryItem(name: "url", value: destination.absoluteString)]
        } else {
            components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        }
        guard let url = components.url else {
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
