import UIKit
import WebKit

/// Turns any page URL into downloadable video/audio, including HLS streams.
final class VideoDownloaderViewController: UITableViewController {

    private let urlField = UITextField()
    private let statusLabel = UILabel()
    private let scanner = WKWebView(frame: .zero)
    private var candidates: [MediaCandidate] = []
    private var scannedURL: URL?
    private var pendingURL: URL?

    /// Starts scanning a URL as soon as the view is on screen.
    func begin(url: URL) {
        pendingURL = url
        if isViewLoaded { start(url: url) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Video Downloader"
        view.backgroundColor = .systemBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(closeTapped)
        )

        buildInput()

        scanner.navigationDelegate = self
        scanner.isHidden = true
        view.addSubview(scanner)

        if let pendingURL {
            start(url: pendingURL)
        }

        NotificationCenter.default.addObserver(
            forName: .magdyDownloadURL, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let url = note.object as? URL else { return }
            self.start(url: url)
        }
    }

    private func buildInput() {
        let header = UIView()
        header.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 110)

        urlField.placeholder = "Paste a video page or media link"
        urlField.borderStyle = .roundedRect
        urlField.keyboardType = .webSearch
        urlField.autocorrectionType = .no
        urlField.autocapitalizationType = .none
        urlField.clearButtonMode = .whileEditing
        urlField.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.text = "Scans the page for direct links, HLS and DASH streams."
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let scanButton = UIButton(type: .system)
        scanButton.setTitle("Scan", for: .normal)
        scanButton.setTitleColor(.white, for: .normal)
        scanButton.backgroundColor = .systemBlue
        scanButton.layer.cornerRadius = 8
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        scanButton.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)

        header.addSubview(urlField)
        header.addSubview(scanButton)
        header.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            urlField.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            urlField.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            urlField.trailingAnchor.constraint(equalTo: scanButton.leadingAnchor, constant: -8),
            urlField.heightAnchor.constraint(equalToConstant: 38),

            scanButton.centerYAnchor.constraint(equalTo: urlField.centerYAnchor),
            scanButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            scanButton.widthAnchor.constraint(equalToConstant: 70),
            scanButton.heightAnchor.constraint(equalToConstant: 38),

            statusLabel.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16)
        ])

        tableView.tableHeaderView = header
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let header = tableView.tableHeaderView {
            header.frame.size.height = 110
            tableView.tableHeaderView = header
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func scanTapped() {
        let text = (urlField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = text.magdyNavigable else {
            statusLabel.text = "Enter a page or media link first."
            return
        }
        start(url: url)
    }

    private func start(url: URL) {
        scannedURL = url
        candidates = []
        tableView.reloadData()
        statusLabel.text = "Loading \(url.host ?? url.absoluteString)…"
        scanner.load(URLRequest(url: url))
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        candidates.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let candidate = candidates[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = candidate.title
        content.secondaryText = candidate.kind.label
        content.image = UIImage(systemName: candidate.kind.symbolName)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let candidate = candidates[indexPath.row]

        scanner.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            switch candidate.kind {
            case .hls:
                DownloadManager.shared.startHLS(
                    url: candidate.url,
                    referer: self.scannedURL,
                    cookies: cookies
                )
            default:
                DownloadManager.shared.start(
                    url: candidate.url,
                    referer: self.scannedURL,
                    cookies: cookies
                )
            }
            self.dismiss(animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if candidates.isEmpty { return nil }
        return "\(candidates.count) source\(candidates.count == 1 ? "" : "s") found"
    }
}

// MARK: - Scanning

extension VideoDownloaderViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        statusLabel.text = "Scanning…"
        MediaScanner.scan(webView: webView) { [weak self] candidates in
            DispatchQueue.main.async {
                guard let self else { return }
                self.candidates = candidates
                self.tableView.reloadData()
                self.statusLabel.text = candidates.isEmpty
                    ? "No downloadable media found on this page."
                    : "Tap a source to download it."
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        statusLabel.text = "Could not load that page: \(error.localizedDescription)"
    }
}
