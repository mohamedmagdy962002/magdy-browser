import UIKit
import WebKit

/// Turns any page URL into downloadable video/audio, including HLS streams.
final class VideoDownloaderViewController: UITableViewController {

    private let urlField = UITextField()
    private let statusLabel = UILabel()
    private let dataStore: WKWebsiteDataStore
    private lazy var scanner: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    private var downloadObserver: NSObjectProtocol?
    private var candidates: [MediaCandidate] = []
    private var scannedURL: URL?
    private var pendingURL: URL?
    private var scanGeneration = 0

    private static let directExtensions: Set<String> = [
        "m3u8", "mpd", "mp4", "m4v", "mov", "webm", "mkv", "avi",
        "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "zip", "pdf", "apk", "epub"
    ]

    init(dataStore: WKWebsiteDataStore = .default()) {
        self.dataStore = dataStore
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let downloadObserver {
            NotificationCenter.default.removeObserver(downloadObserver)
        }
    }

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

        downloadObserver = NotificationCenter.default.addObserver(
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
        urlField.borderStyle = .none
        urlField.backgroundColor = Theme.card
        urlField.layer.cornerRadius = Theme.corner
        urlField.layer.cornerCurve = .continuous
        urlField.font = Theme.body(15, weight: .medium)
        urlField.textColor = Theme.textPrimary
        urlField.keyboardType = .webSearch
        urlField.autocorrectionType = .no
        urlField.autocapitalizationType = .none
        urlField.clearButtonMode = .whileEditing
        urlField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        urlField.leftViewMode = .always
        urlField.translatesAutoresizingMaskIntoConstraints = false
        Theme.floatingShadow(urlField)

        statusLabel.text = "Scans the page for direct links, HLS and DASH streams."
        statusLabel.font = Theme.body(13)
        statusLabel.textColor = Theme.textSecondary
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let scanButton = UIButton(type: .system)
        scanButton.setTitle("Scan", for: .normal)
        scanButton.titleLabel?.font = Theme.headline(15, weight: .semibold)
        scanButton.setTitleColor(.white, for: .normal)
        scanButton.backgroundColor = Theme.primary
        scanButton.layer.cornerRadius = 12
        scanButton.layer.cornerCurve = .continuous
        scanButton.translatesAutoresizingMaskIntoConstraints = false
        scanButton.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
        Theme.fabShadow(scanButton)

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
        // Only resize when needed — reassigning tableHeaderView every layout pass
        // loops forever on UITableViewController (reassign re-triggers layout).
        if let header = tableView.tableHeaderView, header.frame.size.height != 110 {
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
        scanGeneration &+= 1
        let generation = scanGeneration
        scannedURL = url
        candidates = []
        tableView.reloadData()
        urlField.text = url.absoluteString

        if let kind = directKind(for: url) {
            scanner.stopLoading()
            guard kind != .dash else {
                statusLabel.text = "DASH manifests are not supported. Open the page and choose another source."
                return
            }
            statusLabel.text = "Starting download…"
            scanner.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                DispatchQueue.main.async {
                    guard let self, self.scanGeneration == generation else { return }
                    self.download(url, kind: kind, referer: self.scannedURL, cookies: cookies)
                    self.dismiss(animated: true)
                }
            }
            return
        }

        statusLabel.text = "Loading \(url.host ?? url.absoluteString)…"
        scanner.load(URLRequest(url: url))
    }

    private func directKind(for url: URL) -> MediaCandidate.Kind? {
        let ext = url.pathExtension.lowercased()
        guard Self.directExtensions.contains(ext) else { return nil }
        switch ext {
        case "m3u8": return .hls
        case "mpd": return .dash
        case "mp4", "m4v", "mov", "webm", "mkv", "avi": return .video
        case "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus": return .audio
        default: return .file
        }
    }

    private func download(_ url: URL, kind: MediaCandidate.Kind, referer: URL?, cookies: [HTTPCookie]) {
        switch kind {
        case .hls:
            DownloadManager.shared.startHLS(url: url, referer: referer, cookies: cookies)
        case .dash:
            statusLabel.text = "DASH manifests are not supported."
        default:
            DownloadManager.shared.start(url: url, referer: referer, cookies: cookies)
        }
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
        content.textProperties.font = Theme.body(15, weight: .semibold)
        content.secondaryText = candidate.kind.label
        content.secondaryTextProperties.color = Theme.textSecondary
        content.image = UIImage(systemName: candidate.kind.symbolName)
        content.imageProperties.tintColor = Theme.primary
        cell.contentConfiguration = content
        cell.backgroundColor = Theme.card
        cell.layer.cornerRadius = Theme.corner
        cell.layer.cornerCurve = .continuous
        cell.selectionStyle = .none
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let candidate = candidates[indexPath.row]
        guard candidate.kind != .dash else {
            statusLabel.text = "DASH manifests are not supported. Choose another source."
            return
        }
        let generation = scanGeneration
        scanner.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            DispatchQueue.main.async {
                guard let self, self.scanGeneration == generation else { return }
                self.download(candidate.url, kind: candidate.kind, referer: self.scannedURL, cookies: cookies)
                self.dismiss(animated: true)
            }
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if candidates.isEmpty { return nil }
        return "\(candidates.count) source\(candidates.count == 1 ? "" : "s") found"
    }
}

// MARK: - Scanning

extension VideoDownloaderViewController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.targetFrame?.isMainFrame != false,
           let url = navigationAction.request.url,
           directKind(for: url) != nil {
            decisionHandler(.cancel)
            start(url: url)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        statusLabel.text = "Scanning…"
        let generation = scanGeneration
        MediaScanner.scan(webView: webView) { [weak self] candidates in
            DispatchQueue.main.async {
                guard let self, self.scanGeneration == generation else { return }
                self.candidates = candidates
                self.tableView.reloadData()
                self.statusLabel.text = candidates.isEmpty
                    ? "No downloadable media found on this page."
                    : "Tap a source to download it."
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        statusLabel.text = "Could not load that page: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        statusLabel.text = "Could not load that page: \(error.localizedDescription)"
    }
}
