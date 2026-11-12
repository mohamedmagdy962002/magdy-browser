import UIKit
import WebKit

final class BrowserViewController: UIViewController, UITextFieldDelegate {

    private let store = TabStore()
    private var activeTab: BrowserTab?

    private let webContainer = UIView()
    private let addressRow = UIStackView()
    private let addressField = UITextField()
    private let reloadButton = UIButton(type: .system)
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let toolbar = UIStackView()
    private let tabButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)

    private var openURLObserver: NSObjectProtocol?
    private var downloadURLObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildUI()
        openNewTab(privateMode: UserDefaultsKey.bool(UserDefaultsKey.defaultPrivate, default: false))

        openURLObserver = NotificationCenter.default.addObserver(
            forName: .magdyOpenURL, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let url = note.object as? URL else { return }
            self.open(url: url, privateMode: false)
        }

        downloadURLObserver = NotificationCenter.default.addObserver(
            forName: .magdyDownloadURL, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let url = note.object as? URL else { return }
            self.handleIncomingDownload(url)
        }
    }

    deinit {
        if let openURLObserver {
            NotificationCenter.default.removeObserver(openURLObserver)
        }
        if let downloadURLObserver {
            NotificationCenter.default.removeObserver(downloadURLObserver)
        }
    }

    // MARK: - Layout

    private func buildUI() {
        addressRow.axis = .horizontal
        addressRow.spacing = 8
        addressRow.translatesAutoresizingMaskIntoConstraints = false

        addressField.placeholder = "Search or enter website"
        addressField.keyboardType = .webSearch
        addressField.returnKeyType = .go
        addressField.autocorrectionType = .no
        addressField.autocapitalizationType = .none
        addressField.clearButtonMode = .whileEditing
        addressField.delegate = self
        addressField.borderStyle = .roundedRect
        addressField.font = .systemFont(ofSize: 15)

        reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        reloadButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)
        reloadButton.widthAnchor.constraint(equalToConstant: 40).isActive = true

        addressRow.addArrangedSubview(addressField)
        addressRow.addArrangedSubview(reloadButton)

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true
        progressBar.progressTintColor = .systemBlue

        webContainer.translatesAutoresizingMaskIntoConstraints = false
        webContainer.backgroundColor = .systemBackground

        toolbar.axis = .horizontal
        toolbar.distribution = .fillEqually
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        forwardButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        tabButton.setImage(UIImage(systemName: "square.on.square"), for: .normal)
        tabButton.addTarget(self, action: #selector(tabsTapped), for: .touchUpInside)

        let newTabButton = UIButton(type: .system)
        newTabButton.setImage(UIImage(systemName: "plus"), for: .normal)
        newTabButton.addTarget(self, action: #selector(newTabTapped), for: .touchUpInside)

        let menuButton = UIButton(type: .system)
        menuButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = makeMenu()

        toolbar.addArrangedSubview(backButton)
        toolbar.addArrangedSubview(forwardButton)
        toolbar.addArrangedSubview(tabButton)
        toolbar.addArrangedSubview(newTabButton)
        toolbar.addArrangedSubview(menuButton)

        view.addSubview(addressRow)
        view.addSubview(progressBar)
        view.addSubview(webContainer)
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            addressRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            addressRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            addressRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            addressRow.heightAnchor.constraint(equalToConstant: 40),

            progressBar.topAnchor.constraint(equalTo: addressRow.bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2),

            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 52),

            webContainer.topAnchor.constraint(equalTo: progressBar.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: toolbar.topAnchor)
        ])
    }

    private func makeMenu() -> UIMenu {
        let privateTab = UIAction(title: L.t("private_tab"), image: UIImage(systemName: "eye.slash")) { [weak self] _ in
            self?.openNewTab(privateMode: true)
        }
        let favorite = UIAction(title: L.t("add_to_favorites"), image: UIImage(systemName: "star")) { [weak self] _ in
            self?.addCurrentPageToFavorites()
        }
        let media = UIAction(title: L.t("download_media"), image: UIImage(systemName: "arrow.down.circle")) { [weak self] _ in
            self?.downloadMediaFromPage()
        }
        let downloader = UIAction(title: "Video Downloader", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in
            self?.openVideoDownloader()
        }
        let reader = UIAction(title: L.t("reader_mode"), image: UIImage(systemName: "text.alignleft")) { [weak self] _ in
            self?.openReaderMode()
        }
        let find = UIAction(title: L.t("find_in_page"), image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in
            self?.openFindInPage()
        }
        let closeAll = UIAction(title: L.t("close_all_tabs"), image: UIImage(systemName: "xmark.circle"), attributes: .destructive) { [weak self] _ in
            self?.closeAllTabs()
        }
        return UIMenu(children: [privateTab, favorite, media, downloader, reader, find, closeAll])
    }

    // MARK: - Video downloader

    private func openVideoDownloader() {
        let controller = VideoDownloaderViewController()
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(navigation, animated: true)
    }

    /// Handles a URL that arrived from the share sheet or another app.
    private func handleIncomingDownload(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let direct = ["mp4", "m4v", "mov", "webm", "mkv", "mp3", "m4a", "aac", "wav", "flac", "zip", "pdf", "apk"]

        if ext == "m3u8" {
            activeTab?.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                DownloadManager.shared.startHLS(url: url, referer: nil, cookies: cookies)
            }
            return
        }
        if direct.contains(ext) {
            activeTab?.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                DownloadManager.shared.start(url: url, referer: nil, cookies: cookies)
            }
            return
        }
        let controller = VideoDownloaderViewController()
        let navigation = UINavigationController(rootViewController: controller)
        present(navigation, animated: true) {
            controller.begin(url: url)
        }
    }

    // MARK: - Reader mode / find

    private func openReaderMode() {
        guard let tab = activeTab else { return }
        ReaderMode.extract(from: tab.webView) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let article):
                    let reader = ReaderViewController(article: article)
                    let navigation = UINavigationController(rootViewController: reader)
                    self.present(navigation, animated: true)
                case .failure:
                    let alert = UIAlertController(
                        title: L.t("no_media_found"),
                        message: "No readable content found on this page.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func openFindInPage() {
        guard let tab = activeTab else { return }
        let controller = FindInPageController(webView: tab.webView)
        controller.modalPresentationStyle = .overCurrentContext
        present(controller, animated: true)
    }

    // MARK: - Tabs

    private func openNewTab(privateMode: Bool) {
        let tab = store.newTab(privateMode: privateMode)
        activate(tab)
    }

    private func activate(_ tab: BrowserTab) {
        activeTab?.webView.removeFromSuperview()
        activeTab = tab

        tab.onTitleChange = { [weak self] _ in self?.refreshToolbar() }
        tab.onLoadingChange = { [weak self] tab, loading in
            self?.refreshToolbar()
            self?.reloadButton.setImage(
                UIImage(systemName: loading ? "xmark" : "arrow.clockwise"),
                for: .normal
            )
        }
        tab.onProgress = { [weak self] tab, progress in
            self?.progressBar.isHidden = progress >= 1 || progress == 0
            self?.progressBar.setProgress(Float(progress), animated: true)
        }

        webContainer.addSubview(tab.webView)
        tab.webView.frame = webContainer.bounds
        tab.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        refreshToolbar()
    }

    private func refreshToolbar() {
        guard let tab = activeTab else { return }
        tabButton.setTitle("\(store.tabs.count)", for: .normal)
        backButton.isEnabled = tab.webView.canGoBack
        forwardButton.isEnabled = tab.webView.canGoForward
        if !addressField.isFirstResponder, let url = tab.webView.url {
            addressField.text = url.absoluteString
        }
    }

    private func closeAllTabs() {
        store.closeAll()
        openNewTab(privateMode: false)
    }

    private func open(url: URL, privateMode: Bool) {
        let tab = store.newTab(privateMode: privateMode)
        activate(tab)
        tab.load(url: url)
    }

    // MARK: - Actions

    @objc private func reloadTapped() {
        guard let tab = activeTab else { return }
        if tab.webView.isLoading {
            tab.stopLoading()
        } else {
            tab.reload()
        }
    }

    @objc private func backTapped() { activeTab?.goBack() }

    @objc private func forwardTapped() { activeTab?.goForward() }

    @objc private func newTabTapped() {
        openNewTab(privateMode: UserDefaultsKey.bool(UserDefaultsKey.defaultPrivate, default: false))
    }

    @objc private func tabsTapped() {
        let sheet = UIAlertController(title: "Tabs", message: nil, preferredStyle: .actionSheet)
        for (index, tab) in store.tabs.enumerated() {
            let label = tab.title.isEmpty ? "Tab \(index + 1)" : tab.title
            sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.activate(tab)
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = tabButton
            popover.sourceRect = tabButton.bounds
        }
        present(sheet, animated: true)
    }

    private func addCurrentPageToFavorites() {
        guard let tab = activeTab, let url = tab.webView.url else { return }
        FavoritesStore.shared.add(url: url, title: tab.title)
        let alert = UIAlertController(
            title: "Saved",
            message: "Added \(url.host ?? "page") to Favorites.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Media downloads

    private func downloadMediaFromPage() {
        guard let tab = activeTab else { return }
        let script = """
        (function () {
          const out = [];
          const add = (url, title) => {
            if (!url) return;
            const absolute = new URL(url, document.baseURI).href;
            if (!out.some((item) => item.url === absolute)) {
              out.push({ url: absolute, title: title || absolute });
            }
          };
          document.querySelectorAll('video, source').forEach((el) => add(el.src || el.getAttribute('src'), 'video'));
          document.querySelectorAll('a[href]').forEach((a) => {
            const href = a.href || '';
            if (/\\.(mp4|m4v|mov|webm|mkv|mp3|m4a|aac|wav|flac|zip|pdf|apk)(\\?|#|$)/i.test(href)) {
              add(href, (a.innerText || '').trim() || href);
            }
          });
          return JSON.stringify(out);
        })();
        """

        tab.webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, let json = result as? String, let data = json.data(using: .utf8) else {
                self?.showNoMediaAlert()
                return
            }
            let items = (try? JSONDecoder().decode([MediaItem].self, from: data)) ?? []
            guard !items.isEmpty else {
                self.showNoMediaAlert()
                return
            }
            self.presentMediaPicker(items, from: tab)
        }
    }

    private func showNoMediaAlert() {
        let alert = UIAlertController(
            title: "No media found",
            message: "This page has no direct video, audio or file links.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentMediaPicker(_ items: [MediaItem], from tab: BrowserTab) {
        let picker = MediaPickerViewController(items: items)
        picker.onSelect = { [weak self, weak tab] item in
            guard let self, let tab, let url = URL(string: item.url) else { return }
            tab.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                DownloadManager.shared.start(url: url, referer: tab.webView.url, cookies: cookies)
            }
        }
        let navigation = UINavigationController(rootViewController: picker)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(navigation, animated: true)
    }
}

// MARK: - Address field

extension BrowserViewController {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        guard let tab = activeTab else { return true }
        let input = textField.text ?? ""
        if let url = input.magdyNavigable {
            tab.load(url: url)
        } else {
            tab.loadStartPage()
        }
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        textField.text = ""
    }
}
