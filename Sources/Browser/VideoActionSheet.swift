import UIKit

/// Aloha reference #2: bottom sheet shown when a video is tapped on the page —
/// the source URL plus Play / Download video / Copy video link / Share link.
final class VideoActionSheet: UIViewController {

    private let url: URL
    private let pageTitle: String
    private let cookies: [HTTPCookie]
    var onPlay: ((URL) -> Void)?

    private let urlLabel = UILabel()
    private let rowsStack = UIStackView()

    init(url: URL, title: String, cookies: [HTTPCookie]) {
        self.url = url
        self.pageTitle = title
        self.cookies = cookies
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.canvas
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(closeTapped)
        )

        urlLabel.text = url.absoluteString
        urlLabel.font = Theme.headline(15, weight: .semibold)
        urlLabel.textColor = Theme.textPrimary
        urlLabel.numberOfLines = 2
        urlLabel.lineBreakMode = .byTruncatingMiddle

        rowsStack.axis = .vertical
        rowsStack.spacing = 2

        func row(_ title: String, symbol: String, tint: UIColor = Theme.textPrimary, action: @escaping () -> Void) {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.title = title
            config.image = UIImage(systemName: symbol)
            config.imagePadding = 14
            config.baseForegroundColor = tint
            config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 6, bottom: 14, trailing: 6)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = Theme.body(16)
                return outgoing
            }
            button.configuration = config
            button.contentHorizontalAlignment = .leading
            button.backgroundColor = Theme.card
            button.layer.cornerRadius = Theme.cornerSmall
            button.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            button.actionToRun = action
            rowsStack.addArrangedSubview(button)
        }

        row("Play", symbol: "play.fill", tint: Theme.primary) { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) { self.onPlay?(self.url) }
        }
        row("Download video", symbol: "arrow.down.circle") { [weak self] in
            guard let self else { return }
            self.dismiss(animated: true) {
                DownloadOptionsSheet.present(
                    url: self.url, referer: nil, cookies: self.cookies,
                    presenter: self.presentingViewController ?? self
                )
            }
        }
        row("Copy video link", symbol: "doc.on.doc") { [weak self] in
            UIPasteboard.general.string = self?.url.absoluteString
        }
        row("Share link", symbol: "square.and.arrow.up") { [weak self] in
            guard let self else { return }
            let sheet = UIActivityViewController(activityItems: [self.url.absoluteString], applicationActivities: nil)
            self.present(sheet, animated: true)
        }

        let stack = UIStackView(arrangedSubviews: [urlLabel, rowsStack])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.gutter),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.gutter),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18)
        ])
    }

    /// Present inside a page sheet with grabber, Aloha-style.
    static func present(url: URL, title: String, cookies: [HTTPCookie], presenter: UIViewController, onPlay: @escaping (URL) -> Void) {
        let sheet = VideoActionSheet(url: url, title: title, cookies: cookies)
        sheet.onPlay = onPlay
        let nav = UINavigationController(rootViewController: sheet)
        if let page = nav.sheetPresentationController {
            page.detents = [.medium(), .large()]
            page.prefersGrabberVisible = true
        }
        presenter.present(nav, animated: true)
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func rowTapped(_ sender: UIButton) {
        sender.runAction?()
    }
}

private extension UIButton {
    private static var actionKey: UInt8 = 0

    var actionToRun: (() -> Void)? {
        get { objc_getAssociatedObject(self, &Self.actionKey) as? () -> Void }
        set { objc_setAssociatedObject(self, &Self.actionKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }

    var runAction: (() -> Void)? { actionToRun }
}
