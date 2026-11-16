import UIKit
import WebKit
import CoreImage

final class BrowserViewController: UIViewController, UITextFieldDelegate {

    static let homepageURLKey = "magdy.homepageURL"

    private let store = TabStore()
    private var activeTab: BrowserTab?

    private let omnibox = UIView()
    private let webContainer = UIView()
    private let addressRow = UIStackView()
    private let addressField = UITextField()
    private let reloadButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let progressBar = UIProgressView(progressViewStyle: .default)
    private let toolbar = UIStackView()
    private let tabButton = UIButton(type: .system)
    /// "Video is playing" mini banner (Aloha ref) under the omnibox.
    private let playerBanner = PlayerSessionBanner()
    private var bannerObserver: NSObjectProtocol?
    private var downloadsObserver: NSObjectProtocol?
    private var omniboxObserver: NSObjectProtocol?
    /// Position anchor sets swapped by the "Search Bar Position" setting.
    private var topConstraints: [NSLayoutConstraint] = []
    private var bottomConstraints: [NSLayoutConstraint] = []
    /// Frosted card behind the suggestion rows.
    private var suggestionsGlass: UIVisualEffectView?
    private let backButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let downloadFAB = UIButton(type: .system)

    private var openURLObserver: NSObjectProtocol?
    private var downloadURLObserver: NSObjectProtocol?
    private var nightModeObserver: NSObjectProtocol?
    private var closedTabs: [TabGridViewController.ClosedTab] = []
    private let suggestionsTable = UITableView(frame: .zero, style: .plain)
    private var suggestions: [String] = []
    private var lastToolbarY: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildUI()
        openNewTab(privateMode: UserDefaultsKey.bool(UserDefaultsKey.defaultPrivate, default: false))
        offerSessionRestore()

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

        nightModeObserver = NotificationCenter.default.addObserver(
            forName: .magdyNightModeChanged, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let enabled = note.object as? Bool, let tab = self.activeTab else { return }
            tab.setNightMode(enabled)
        }
    }

    deinit {
        if let openURLObserver {
            NotificationCenter.default.removeObserver(openURLObserver)
        }
        if let downloadURLObserver {
            NotificationCenter.default.removeObserver(downloadURLObserver)
        }
        if let nightModeObserver {
            NotificationCenter.default.removeObserver(nightModeObserver)
        }
    }

    // MARK: - Layout

    private func buildUI() {
        addressRow.axis = .horizontal
        addressRow.spacing = 8
        addressRow.translatesAutoresizingMaskIntoConstraints = false

        addressField.placeholder = L.t("search_placeholder")
        addressField.keyboardType = .webSearch
        addressField.returnKeyType = .go
        addressField.autocorrectionType = .no
        addressField.autocapitalizationType = .none
        addressField.clearButtonMode = .whileEditing
        addressField.delegate = self
        addressField.font = Theme.body(16, weight: .medium)
        addressField.textColor = Theme.textPrimary
        addressField.backgroundColor = .clear
        addressField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        addressField.leftViewMode = .always
        addressField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 1))
        addressField.rightViewMode = .unlessEditing
        addressField.clipsToBounds = true

        reloadButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        reloadButton.tintColor = Theme.textSecondary
        reloadButton.addTarget(self, action: #selector(reloadTapped), for: .touchUpInside)
        reloadButton.widthAnchor.constraint(equalToConstant: 40).isActive = true

        addressRow.addArrangedSubview(addressField)
        addressRow.addArrangedSubview(reloadButton)

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true
        progressBar.progressTintColor = Theme.primary
        progressBar.trackTintColor = .clear

        webContainer.translatesAutoresizingMaskIntoConstraints = false
        webContainer.backgroundColor = Theme.canvas

        toolbar.axis = .horizontal
        toolbar.distribution = .fillEqually
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = Theme.textPrimary
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        forwardButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        forwardButton.tintColor = Theme.textPrimary
        forwardButton.addTarget(self, action: #selector(forwardTapped), for: .touchUpInside)
        tabButton.setImage(UIImage(systemName: "square.on.square"), for: .normal)
        tabButton.tintColor = Theme.textPrimary
        tabButton.addTarget(self, action: #selector(tabsTapped), for: .touchUpInside)

        // Periwinkle glass accent circle for "new tab" (Stitch Liquid ref).
        let newTabButton = UIButton(type: .system)
        newTabButton.setImage(UIImage(systemName: "plus"), for: .normal)
        newTabButton.tintColor = .white
        newTabButton.backgroundColor = Theme.primary
        newTabButton.layer.cornerRadius = 15
        newTabButton.layer.cornerCurve = .continuous
        newTabButton.addTarget(self, action: #selector(newTabTapped), for: .touchUpInside)

        let menuButton = self.menuButton
        menuButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        menuButton.tintColor = Theme.primary
        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)

        toolbar.addArrangedSubview(backButton)
        toolbar.addArrangedSubview(forwardButton)
        toolbar.addArrangedSubview(tabButton)
        toolbar.addArrangedSubview(newTabButton)
        toolbar.addArrangedSubview(menuButton)

        // Floating primary action, shown on the start page.
        downloadFAB.setTitle("  Download video", for: .normal)
        downloadFAB.setImage(UIImage(systemName: "arrow.down.circle.fill"), for: .normal)
        downloadFAB.titleLabel?.font = Theme.headline(15, weight: .semibold)
        downloadFAB.tintColor = .white
        downloadFAB.setTitleColor(.white, for: .normal)
        downloadFAB.backgroundColor = Theme.primary
        downloadFAB.layer.cornerRadius = 26
        downloadFAB.layer.cornerCurve = .continuous
        downloadFAB.contentEdgeInsets = UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 20)
        downloadFAB.addTarget(self, action: #selector(openVideoDownloader), for: .touchUpInside)
        downloadFAB.translatesAutoresizingMaskIntoConstraints = false
        downloadFAB.isHidden = true

        // Liquid glass skin: frosted blur under the address row. No clipping on
        // the host — it would kill the drop shadow that separates it from pages.
        omnibox.backgroundColor = .clear
        omnibox.layer.cornerRadius = 26
        omnibox.layer.cornerCurve = .continuous
        let omniboxGlass = Theme.liquidGlassView(corner: 26)
        omnibox.addSubview(omniboxGlass)
        Theme.floatingShadow(omnibox)
        omnibox.translatesAutoresizingMaskIntoConstraints = false

        let toolbarChrome = UIView()
        // Liquid glass dock, flush with the screen edges and the tab bar below
        // (rounded top corners only) so the two rows read as one modern bottom bar.
        toolbarChrome.backgroundColor = .clear
        toolbarChrome.layer.cornerRadius = 22
        toolbarChrome.layer.cornerCurve = .continuous
        toolbarChrome.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let toolbarGlass = Theme.liquidGlassView(corner: 22)
        toolbarGlass.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        toolbarChrome.addSubview(toolbarGlass)
        Theme.floatingShadow(toolbarChrome)
        toolbarChrome.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(omnibox)
        omnibox.addSubview(addressRow)
        view.addSubview(progressBar)
        view.addSubview(webContainer)
        view.addSubview(toolbarChrome)
        toolbarChrome.addSubview(toolbar)
        view.addSubview(downloadFAB)

        NSLayoutConstraint.activate([
            omniboxGlass.topAnchor.constraint(equalTo: omnibox.topAnchor),
            omniboxGlass.leadingAnchor.constraint(equalTo: omnibox.leadingAnchor),
            omniboxGlass.trailingAnchor.constraint(equalTo: omnibox.trailingAnchor),
            omniboxGlass.bottomAnchor.constraint(equalTo: omnibox.bottomAnchor),

            toolbarGlass.topAnchor.constraint(equalTo: toolbarChrome.topAnchor),
            toolbarGlass.leadingAnchor.constraint(equalTo: toolbarChrome.leadingAnchor),
            toolbarGlass.trailingAnchor.constraint(equalTo: toolbarChrome.trailingAnchor),
            toolbarGlass.bottomAnchor.constraint(equalTo: toolbarChrome.bottomAnchor)
        ])

        // Omnibox suggestions overlay — frosted glass card behind the rows.
        let suggestionsGlass = Theme.liquidGlassView(corner: 22)
        self.suggestionsGlass = suggestionsGlass
        suggestionsTable.backgroundColor = .clear
        suggestionsTable.layer.cornerRadius = 22
        suggestionsTable.layer.cornerCurve = .continuous
        suggestionsTable.separatorStyle = .none
        suggestionsTable.register(UITableViewCell.self, forCellReuseIdentifier: "suggestion")
        suggestionsTable.dataSource = self
        suggestionsTable.delegate = self
        suggestionsTable.isHidden = true
        suggestionsGlass.isHidden = true
        suggestionsTable.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(suggestionsTable)
        suggestionsGlass.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(suggestionsGlass, belowSubview: suggestionsTable)
        view.bringSubviewToFront(suggestionsTable)

        Theme.fabShadow(downloadFAB)

        view.addSubview(playerBanner)

        // Position-dependent anchors: two full sets, swapped by the
        // "Search Bar Position" setting (omnibox top = default, bottom = Aloha).
        let top = UserDefaults.standard.bool(forKey: UserDefaultsKey.omniboxBottomKey) == false
        let omniboxTop = omnibox.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        let omniboxBottom = omnibox.bottomAnchor.constraint(equalTo: toolbarChrome.topAnchor, constant: -8)
        let progressTop = progressBar.topAnchor.constraint(equalTo: omnibox.bottomAnchor)
        let progressTopAlt = progressBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        let webTop = webContainer.topAnchor.constraint(equalTo: progressBar.bottomAnchor)
        let webTopAlt = webContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        let webBottom = webContainer.bottomAnchor.constraint(equalTo: toolbarChrome.topAnchor)
        let webBottomAlt = webContainer.bottomAnchor.constraint(equalTo: omnibox.topAnchor, constant: -2)
        let suggestionsTop = suggestionsTable.topAnchor.constraint(equalTo: omnibox.bottomAnchor, constant: 8)
        let suggestionsBottom = suggestionsTable.bottomAnchor.constraint(equalTo: omnibox.topAnchor, constant: -8)
        let bannerTop = playerBanner.topAnchor.constraint(equalTo: omnibox.bottomAnchor, constant: 6)
        let bannerBottom = playerBanner.bottomAnchor.constraint(equalTo: omnibox.topAnchor, constant: -6)
        let fabBottom = downloadFAB.bottomAnchor.constraint(equalTo: toolbarChrome.topAnchor, constant: -16)
        let fabBottomAlt = downloadFAB.bottomAnchor.constraint(equalTo: omnibox.topAnchor, constant: -16)
        topConstraints = [omniboxTop, progressTop, webTop, webBottom, suggestionsTop, bannerTop, fabBottom]
        bottomConstraints = [omniboxBottom, progressTopAlt, webTopAlt, webBottomAlt, suggestionsBottom, bannerBottom, fabBottomAlt]
        NSLayoutConstraint.activate(top ? topConstraints : bottomConstraints)

        NSLayoutConstraint.activate([
            // Static omnibox sizing (position anchors are in the top/bottom sets).
            omnibox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            omnibox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            omnibox.heightAnchor.constraint(equalToConstant: 52),

            addressRow.leadingAnchor.constraint(equalTo: omnibox.leadingAnchor, constant: 8),
            addressRow.trailingAnchor.constraint(equalTo: omnibox.trailingAnchor, constant: -8),
            addressRow.centerYAnchor.constraint(equalTo: omnibox.centerYAnchor),
            addressRow.heightAnchor.constraint(equalToConstant: 36),

            downloadFAB.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            downloadFAB.heightAnchor.constraint(equalToConstant: 48),

            // Layout guards: the omnibox can never stretch beyond its capsule,
            // no matter which position set is active (fixes bottom-mode stretch).
            omnibox.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor),
            omnibox.bottomAnchor.constraint(lessThanOrEqualTo: toolbarChrome.topAnchor, constant: -8),

            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBar.heightAnchor.constraint(equalToConstant: 2),

            // Dock is flush: full width, sitting directly on the tab bar.
            toolbarChrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbarChrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarChrome.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbarChrome.heightAnchor.constraint(equalToConstant: 54),

            toolbar.leadingAnchor.constraint(equalTo: toolbarChrome.leadingAnchor, constant: 4),
            toolbar.trailingAnchor.constraint(equalTo: toolbarChrome.trailingAnchor, constant: -4),
            toolbar.topAnchor.constraint(equalTo: toolbarChrome.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: toolbarChrome.bottomAnchor),

            webContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            suggestionsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            suggestionsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            suggestionsTable.heightAnchor.constraint(lessThanOrEqualToConstant: 260),

            playerBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            playerBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            playerBanner.heightAnchor.constraint(equalToConstant: 46),

            suggestionsGlass.topAnchor.constraint(equalTo: suggestionsTable.topAnchor),
            suggestionsGlass.leadingAnchor.constraint(equalTo: suggestionsTable.leadingAnchor),
            suggestionsGlass.trailingAnchor.constraint(equalTo: suggestionsTable.trailingAnchor),
            suggestionsGlass.bottomAnchor.constraint(equalTo: suggestionsTable.bottomAnchor)
        ])

        // Swipe on the toolbar switches tabs.
        toolbarChrome.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(toolbarSwiped(_:))))

        // Keep the banner in sync with the audio session.
        playerBanner.onStop = { [weak self] in
            PlayerSession.shared.stop()
            self?.playerBanner.isHidden = true
        }
        playerBanner.onDownload = { [weak self] in
            guard let self, let url = PlayerSession.shared.url else { return }
            DownloadOptionsSheet.present(
                url: url, referer: nil, cookies: PlayerSession.shared.cookies, presenter: self
            )
        }
        playerBanner.onExpand = { [weak self] in
            guard let self, let url = PlayerSession.shared.url else { return }
            self.presentVideoPlayer(url: url, title: PlayerSession.shared.title ?? "Video")
        }
        bannerObserver = NotificationCenter.default.addObserver(
            forName: PlayerSession.bannerChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.playerBanner.isHidden = PlayerSession.shared.player == nil
            self.playerBanner.refreshDownloadBadge()
        }
        downloadsObserver = NotificationCenter.default.addObserver(
            forName: .magdyDownloadsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.playerBanner.refreshDownloadBadge()
        }
        omniboxObserver = NotificationCenter.default.addObserver(
            forName: .magdyOmniboxChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyOmniboxLayout()
        }
    }

    /// Swaps the omnibox between docked-top and docked-bottom layouts live.
    private func applyOmniboxLayout() {
        let bottom = UserDefaults.standard.bool(forKey: UserDefaultsKey.omniboxBottomKey)
        NSLayoutConstraint.deactivate(bottom ? topConstraints : bottomConstraints)
        NSLayoutConstraint.activate(bottom ? bottomConstraints : topConstraints)
        view.layoutIfNeeded()
    }

    /// ⋯ tap → liquid-glass action panel. Items rebuilt every tap so dynamic
    /// titles (Night Mode, per-site ads) are always current.
    @objc private func menuTapped() {
        present(GlassMenuSheet(items: makeMenuItems()), animated: true)
    }

    private func makeMenuItems() -> [GlassMenuItem] {
        let privateTab = GlassMenuItem(title: L.t("private_tab"), image: UIImage(systemName: "eye.slash"), destructive: false) { [weak self] in
            self?.openNewTab(privateMode: true)
        }
        let favorite = GlassMenuItem(title: L.t("add_to_favorites"), image: UIImage(systemName: "star"), destructive: false) { [weak self] in
            self?.addCurrentPageToFavorites()
        }
        let media = GlassMenuItem(title: L.t("download_media"), image: UIImage(systemName: "arrow.down.circle"), destructive: false) { [weak self] in
            self?.downloadMediaFromPage()
        }
        let downloader = GlassMenuItem(title: "Video Downloader", image: UIImage(systemName: "square.and.arrow.down"), destructive: false) { [weak self] in
            self?.openVideoDownloader()
        }
        let reader = GlassMenuItem(title: L.t("reader_mode"), image: UIImage(systemName: "text.alignleft"), destructive: false) { [weak self] in
            self?.openReaderMode()
        }
        let find = GlassMenuItem(title: L.t("find_in_page"), image: UIImage(systemName: "magnifyingglass"), destructive: false) { [weak self] in
            self?.openFindInPage()
        }
        let closeAll = GlassMenuItem(title: L.t("close_all_tabs"), image: UIImage(systemName: "xmark.circle"), destructive: true) { [weak self] in
            self?.closeAllTabs()
        }
        let desktopSite = GlassMenuItem(title: "Desktop Site", image: UIImage(systemName: "desktopcomputer"), destructive: false) { [weak self] in
            self?.toggleDesktopSite()
        }
        let inSafari = GlassMenuItem(title: "Open in Safari", image: UIImage(systemName: "safari"), destructive: false) { [weak self] in
            self?.openInSafari()
        }
        let copy = GlassMenuItem(title: "Copy Link", image: UIImage(systemName: "doc.on.doc"), destructive: false) { [weak self] in
            self?.copyLink()
        }
        let tabsGrid = GlassMenuItem(title: "All Tabs", image: UIImage(systemName: "square.grid.2x2"), destructive: false) { [weak self] in
            self?.openTabGrid()
        }
        let reopen = GlassMenuItem(title: "Reopen Closed Tab", image: UIImage(systemName: "arrow.uturn.left"), destructive: false) { [weak self] in
            self?.reopenClosedTab()
        }
        let savePDF = GlassMenuItem(title: "Export Page as PDF", image: UIImage(systemName: "doc.richtext"), destructive: false) { [weak self] in
            self?.exportPDF(fullPage: false)
        }
        let screenshot = GlassMenuItem(title: "Full Page Screenshot", image: UIImage(systemName: "camera.viewfinder"), destructive: false) { [weak self] in
            self?.fullPageScreenshot()
        }
        let biggerText = GlassMenuItem(title: "Bigger Text", image: UIImage(systemName: "textformat.size.larger"), destructive: false) { [weak self] in
            self?.adjustSiteZoom(delta: 20)
        }
        let smallerText = GlassMenuItem(title: "Smaller Text", image: UIImage(systemName: "textformat.size.smaller"), destructive: false) { [weak self] in
            self?.adjustSiteZoom(delta: -20)
        }
        let resetText = GlassMenuItem(title: "Reset Text Size", image: UIImage(systemName: "textformat.size"), destructive: false) { [weak self] in
            self?.adjustSiteZoom(delta: nil)
        }
        let clearSite = GlassMenuItem(
            title: "Clear Data for This Site",
            image: UIImage(systemName: "shield.slash"),
            destructive: true
        ) { [weak self] in
            self?.clearSiteData()
        }
        let allowAds = activeTab?.webView.url?.host.map { host -> GlassMenuItem in
            let allowed = BrowserTab.isAdAllowed(host)
            return GlassMenuItem(
                title: allowed ? "Re-enable Ads on This Site" : "Allow Ads on This Site",
                image: UIImage(systemName: allowed ? "shield.fill" : "shield.lefthalf.filled.slash"),
                destructive: false
            ) { [weak self] in
                BrowserTab.setAdAllowed(host, !allowed)
                self?.activeTab?.applyNewRuleLists()
                self?.activeTab?.reload()
            }
        }
        let nightMode = GlassMenuItem(
            title: activeTab?.nightModeEnabled == true ? "Night Mode Off" : "Night Mode On",
            image: UIImage(systemName: "moon"),
            destructive: false
        ) { [weak self] in
            self?.toggleNightMode()
        }
        let qr = GlassMenuItem(title: "Scan QR Code", image: UIImage(systemName: "qrcode.viewfinder"), destructive: false) { [weak self] in
            self?.openQRScanner()
        }
        let shareQR = GlassMenuItem(title: "QR Code of This Page", image: UIImage(systemName: "qrcode"), destructive: false) { [weak self] in
            self?.sharePageQRCode()
        }
        let voice = GlassMenuItem(title: "Voice Search", image: UIImage(systemName: "mic"), destructive: false) { [weak self] in
            self?.openVoiceSearch()
        }
        let readingList = GlassMenuItem(title: "Add to Reading List", image: UIImage(systemName: "book"), destructive: false) { [weak self] in
            self?.saveToReadingList()
        }
        let translate = GlassMenuItem(title: "Translate Page", image: UIImage(systemName: "character.bubble"), destructive: false) { [weak self] in
            self?.translatePage()
        }
        let lockNow = GlassMenuItem(title: "Lock Now", image: UIImage(systemName: "lock"), destructive: false) { [weak self] in
            self?.lockNow()
        }
        let homepage = GlassMenuItem(title: "Homepage", image: UIImage(systemName: "house"), destructive: false) { [weak self] in
            guard let self,
                  let raw = UserDefaults.standard.string(forKey: BrowserViewController.homepageURLKey),
                  let url = URL(string: raw) else { return }
            self.open(url: url, privateMode: false)
        }
        var items: [GlassMenuItem] = [
            tabsGrid, reopen, privateTab, favorite, homepage, readingList, media, downloader,
            reader, find, desktopSite, inSafari, copy, savePDF, screenshot,
            biggerText, smallerText, resetText, nightMode, translate,
            qr, shareQR, voice, clearSite, lockNow, closeAll
        ]
        // RSS/Atom feeds advertised by the current page.
        if let feeds = activeTab?.rssFeeds, !feeds.isEmpty {
            items.insert(
                GlassMenuItem(title: "RSS Feeds", image: UIImage(systemName: "dot.radiowaves.right"), destructive: false) { [weak self] in
                    self?.showRSSFeeds(feeds)
                },
                at: 0
            )
        }
        // Per-site ad allowlist — only shown on a loaded page.
        if let allowAds {
            items.insert(allowAds, at: 0)
        }
        return items
    }

    /// Lists the feeds found on the page; tapping one opens it.
    private func showRSSFeeds(_ feeds: [String]) {
        let sheet = UIAlertController(title: "Feeds on this page", message: nil, preferredStyle: .actionSheet)
        for feed in feeds {
            sheet.addAction(UIAlertAction(title: feed, style: .default) { [weak self] _ in
                guard let url = URL(string: feed) else { return }
                self?.open(url: url, privateMode: false)
            })
        }
        sheet.addAction(UIAlertAction(title: L.t("cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        present(sheet, animated: true)
    }

    /// Saves the whole page (top to bottom) to the photo library.
    private func fullPageScreenshot() {
        guard let tab = activeTab, tab.webView.url != nil else { return }
        let contentSize = tab.webView.scrollView.contentSize
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: contentSize)
        tab.webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let image else { return }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            let alert = UIAlertController(title: "Saved", message: "Full-page screenshot saved to Photos.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
            self?.present(alert, animated: true)
        }
    }

    /// Per-site text zoom: steps ±20% (clamped 50–200), or resets to the global setting when delta is nil.
    private func adjustSiteZoom(delta: Double?) {
        guard let tab = activeTab, let host = tab.webView.url?.host else { return }
        let current = tab.effectiveTextZoom()
        let newZoom = delta.map { min(200, max(50, current + $0)) }
        BrowserTab.setSiteZoom(newZoom == UserDefaults.standard.object(forKey: BrowserTab.textZoomKey) as? Double ? nil : newZoom, for: host)
        tab.applyTextZoomIfNeeded()
    }

    /// Clears cookies, storage and cache belonging to the current site's domain.
    /// Private tabs clear from their own non-persistent store.
    private func clearSiteData() {
        guard let tab = activeTab, let host = tab.webView.url?.host else { return }
        let types: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeDiskCache
        ]
        let store = tab.webView.configuration.websiteDataStore
        store.fetchDataRecords(ofTypes: types) { records in
            let matching = records.filter {
                host == $0.displayName || host.hasSuffix(".\($0.displayName)") || $0.displayName.hasSuffix(".\(host)")
            }
            guard !matching.isEmpty else { return }
            store.removeData(ofTypes: types, for: matching) {
                DispatchQueue.main.async { tab.reload() }
            }
        }
    }

    // MARK: - Video downloader

    @objc private func openVideoDownloader() {
        let controller = VideoDownloaderViewController()
        let navigation = UINavigationController(rootViewController: controller)
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
        }
        present(navigation, animated: true)
    }

    // MARK: - Video player

    private func presentVideoPlayer(url: URL, title: String) {
        let name = title.isEmpty ? url.host ?? "Video" : title
        // Different video while one is playing in the background? Stop the old
        // session first — otherwise two audio streams overlap.
        if let sessionPlayer = PlayerSession.shared.player,
           PlayerSession.shared.url?.absoluteString != url.absoluteString {
            sessionPlayer.pause()
            PlayerSession.shared.stop()
        }
        // Reopen seamlessly when this is the session's own video (banner → expand).
        let reuse = PlayerSession.shared.url?.absoluteString == url.absoluteString
            ? PlayerSession.shared.player : nil
        // Site cookies ride along so authenticated streams download correctly.
        activeTab?.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let player = VideoPlayerController(
                url: url, title: name, cookies: cookies, existingPlayer: reuse
            )
            player.modalPresentationStyle = .fullScreen
            self?.present(player, animated: true)
        }
    }

    // MARK: - Page tools

    /// Generates a QR code image of the current page URL and opens the share sheet.
    private func sharePageQRCode() {
        guard let url = activeTab?.webView.url else { return }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue(url.absoluteString.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return }
        let scale: CGFloat = 8
        let size = CGSize(width: cgImage.width * Int(scale), height: cgImage.height * Int(scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("magdy-qr-\(Int(Date().timeIntervalSince1970)).png")
        guard let data = image.pngData() else { return }
        do {
            try data.write(to: file)
        } catch {
            return
        }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        present(sheet, animated: true)
    }

    private func toggleDesktopSite() {
        guard let tab = activeTab, let url = tab.webView.url else { return }
        let desktop = tab.webView.customUserAgent?.contains("Macintosh") != true
        tab.webView.customUserAgent = desktop
            ? BrowserTab.desktopUserAgent
            : nil
        BrowserTab.rememberUserAgent(host: url.host ?? "", desktop: desktop)
        tab.webView.load(URLRequest(url: url))
    }

    private func openInSafari() {
        guard let url = activeTab?.webView.url else { return }
        UIApplication.shared.open(url)
    }

    private func copyLink() {
        guard let url = activeTab?.webView.url else { return }
        UIPasteboard.general.string = url.absoluteString
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
        tab.lastActivatedAt = Date()
        // Wake FIRST — it may replace tab.webView entirely.
        tab.wake()

        // Only the visible tab may drive chrome UI — background tabs finishing
        // their load must not flicker the progress bar or reload button.
        tab.onTitleChange = { [weak self, weak tab] _ in
            guard let self, let tab, self.activeTab === tab else { return }
            self.refreshToolbar()
        }
        tab.onLoadingChange = { [weak self] changedTab, loading in
            guard let self, self.activeTab === changedTab else { return }
            self.refreshToolbar()
            self.reloadButton.setImage(
                UIImage(systemName: loading ? "xmark" : "arrow.clockwise"),
                for: .normal
            )
            if !loading {
                self.store.persist()
            }
        }
        tab.onProgress = { [weak self] changedTab, progress in
            guard let self, self.activeTab === changedTab else { return }
            self.progressBar.isHidden = progress >= 1 || progress == 0
            self.progressBar.setProgress(Float(progress), animated: true)
        }
        tab.onVideoTapped = { [weak self] url, title in
            guard let self else { return }
            // Aloha-style chooser instead of jumping straight into the player.
            self.activeTab?.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                DispatchQueue.main.async {
                    VideoActionSheet.present(url: url, title: title, cookies: cookies, presenter: self) { target in
                        self.presentVideoPlayer(url: target, title: title)
                    }
                }
            }
        }
        tab.onOpenLink = { [weak self] url, privateMode in
            self?.open(url: url, privateMode: privateMode)
        }
        tab.onQuickAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case "private": self.openNewTab(privateMode: true)
            case "qr": self.openQRScanner()
            case "voice": self.openVoiceSearch()
            case "downloads":
                let downloads = UINavigationController(rootViewController: DownloadsViewController())
                self.present(downloads, animated: true)
            default: break
            }
        }

        // Pull-to-refresh.
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        tab.webView.scrollView.refreshControl = refresh

        // Hide the toolbar while the user scrolls down, bring it back scrolling up.
        tab.webView.scrollView.delegate = self

        webContainer.addSubview(tab.webView)
        tab.webView.frame = webContainer.bounds
        tab.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Apply global page styles to an already-loaded tab (they are per-webView
        // injections, so switching tabs must re-apply them).
        tab.applyNightModeIfNeeded()
        refreshToolbar()
        hibernateInactiveTabs()
    }

    /// Memory Saver: releases pages that have been inactive for over 5 minutes.
    private func hibernateInactiveTabs() {
        let saverOn = UserDefaults.standard.object(forKey: "magdy.memorySaver") as? Bool ?? true
        guard saverOn else { return }
        let cutoff = Date().addingTimeInterval(-300)
        for tab in store.tabs where tab !== activeTab && tab.lastActivatedAt < cutoff {
            tab.hibernate()
        }
    }

    private func refreshToolbar() {
        guard let tab = activeTab else { return }
        tabButton.setTitle("\(store.tabs.count)", for: .normal)
        backButton.isEnabled = tab.webView.canGoBack
        forwardButton.isEnabled = tab.webView.canGoForward
        // The floating download action belongs to the start page only.
        downloadFAB.isHidden = tab.displayURL != nil
        if !addressField.isFirstResponder {
            addressField.text = tab.displayURL?.absoluteString ?? ""
        }
    }

    private func closeAllTabs() {
        for tab in store.tabs {
            closedTabs.append(TabGridViewController.ClosedTab(url: tab.displayURL, isPrivate: tab.isPrivate))
        }
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

    @objc private func pullToRefresh() {
        guard let tab = activeTab else { return }
        tab.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.activeTab?.webView.scrollView.refreshControl?.endRefreshing()
        }
    }

    @objc private func toolbarSwiped(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: view).x
        gesture.setTranslation(.zero, in: view)
        guard abs(translation) > 60,
              let tab = activeTab,
              let index = store.tabs.firstIndex(where: { $0 === tab }) else { return }
        let next = translation < 0 ? min(index + 1, store.tabs.count - 1) : max(index - 1, 0)
        if next != index {
            activate(store.tabs[next])
        }
    }

    @objc private func tabsTapped() {
        openTabGrid()
    }

    private func openTabGrid() {
        let grid = TabGridViewController(
            store: store,
            activeTab: activeTab,
            onActivate: { [weak self] tab in self?.activate(tab) },
            onNewTab: { [weak self] in
                self?.openNewTab(privateMode: UserDefaultsKey.bool(UserDefaultsKey.defaultPrivate, default: false))
            },
            onReopen: { [weak self] closed in self?.closedTabs.append(closed) },
            onClosed: { [weak self] tab in
                guard let self, self.activeTab === tab else { return }
                // The visible tab was closed from the grid — show another tab
                // or start a fresh one so no zombie page stays on screen.
                if let next = self.store.tabs.first {
                    self.activate(next)
                } else {
                    self.openNewTab(privateMode: false)
                }
            }
        )
        let navigation = UINavigationController(rootViewController: grid)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation, animated: true)
    }

    private func reopenClosedTab() {
        guard let last = closedTabs.popLast() else { return }
        let tab = store.newTab(privateMode: last.isPrivate)
        activate(tab)
        if let url = last.url {
            tab.load(url: url)
        }
    }

    /// Asks whether to reopen the tabs that were open when the app was killed.
    private func offerSessionRestore() {
        let saved = store.savedSession()
        guard saved.count > 1 else { return }
        let alert = UIAlertController(
            title: "Restore Session?",
            message: "Reopen the \(saved.count) tabs from your last session.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Restore", style: .default) { [weak self] _ in
            guard let self else { return }
            var lastTab: BrowserTab?
            for entry in saved {
                guard let url = URL(string: entry.url) else { continue }
                let tab = self.store.newTab(privateMode: false)
                self.activate(tab)
                tab.load(url: url)
                lastTab = tab
            }
            if let lastTab {
                self.activate(lastTab)
            }
            self.store.clearSavedSession()
        })
        alert.addAction(UIAlertAction(title: "New Session", style: .cancel) { [weak self] _ in
            self?.store.clearSavedSession()
        })
        present(alert, animated: true)
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
        suggestionsTable.isHidden = true
        suggestionsGlass?.isHidden = true
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

    func textFieldDidEndEditing(_ textField: UITextField) {
        suggestionsTable.isHidden = true
        suggestionsGlass?.isHidden = true
        // Restore the current URL when the user dismisses the keyboard without navigating.
        if (textField.text ?? "").isEmpty {
            textField.text = activeTab?.webView.url?.absoluteString ?? ""
        }
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        guard let current = (textField.text as NSString?)?.replacingCharacters(in: range, with: string) else { return true }
        let query = current.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2, !current.contains(".") && !current.contains(" ") else {
            suggestionsTable.isHidden = true
        suggestionsGlass?.isHidden = true
            return true
        }
        SearchEngine.suggestions(for: query) { [weak self] results in
            // Drop out-of-order responses for queries the user already replaced.
            guard let self, textField.isFirstResponder, textField.text?.trimmingCharacters(in: .whitespaces) == query else { return }
            self.suggestions = results
            self.suggestionsTable.reloadData()
            self.suggestionsTable.isHidden = results.isEmpty
            self.suggestionsGlass?.isHidden = results.isEmpty
        }
        return true
    }
}

// MARK: - Suggestions

extension BrowserViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        suggestions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "suggestion", for: indexPath)
        // Stitch omnibox mock: globe for typed URLs, muted magnifier for searches.
        let query = suggestions[indexPath.row]
        let looksLikeURL = query.contains(".") && !query.contains(" ")
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: looksLikeURL ? "globe" : "magnifyingglass")
        content.imageProperties.tintColor = looksLikeURL ? Theme.primary : Theme.textSecondary
        content.text = query
        content.textProperties.font = Theme.body(15)
        content.textProperties.color = Theme.textPrimary
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let query = suggestions[indexPath.row]
        addressField.text = query
        addressField.resignFirstResponder()
        suggestionsTable.isHidden = true
        suggestionsGlass?.isHidden = true
        guard let tab = activeTab, let url = SearchEngine.effectiveSearchURL(for: query) else { return }
        tab.load(url: url)
    }
}

// MARK: - Scroll behaviour

extension BrowserViewController: UIScrollViewDelegate {
    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard scrollView === activeTab?.webView.scrollView else { return }
        let chromeHeight: CGFloat = 60
        let collapsed = velocity.y > 0.5
        let expanded = velocity.y < -0.5
        var transform = CGAffineTransform.identity
        if collapsed {
            transform = CGAffineTransform(translationX: 0, y: chromeHeight + 20)
        } else if expanded {
            transform = .identity
        }
        UIView.animate(withDuration: 0.25) {
            self.omnibox.transform = transform
            self.progressBar.transform = transform
        }
    }
}

// MARK: - Page tools & integrations

extension BrowserViewController {
    private func exportPDF(fullPage: Bool) {
        guard let tab = activeTab, tab.webView.url != nil else { return }
        tab.exportPDF(fullPage: fullPage) { [weak self] url in
            guard let self, let url else {
                let alert = UIAlertController(title: "Export failed", message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
                self?.present(alert, animated: true)
                return
            }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = self.view
            self.present(sheet, animated: true)
        }
    }

    private func toggleNightMode() {
        guard let tab = activeTab else { return }
        tab.setNightMode(!tab.nightModeEnabled)
    }

    private func openQRScanner() {
        let scanner = QRScannerViewController()
        scanner.onURLFound = { [weak self] url in
            self?.open(url: url, privateMode: false)
        }
        let navigation = UINavigationController(rootViewController: scanner)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation, animated: true)
    }

    private func openVoiceSearch() {
        let search = VoiceSearchViewController()
        search.onText = { [weak self] text in
            guard let self, let url = SearchEngine.effectiveSearchURL(for: text) else { return }
            self.open(url: url, privateMode: false)
        }
        let navigation = UINavigationController(rootViewController: search)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation, animated: true)
    }

    private func saveToReadingList() {
        guard let tab = activeTab else { return }
        ReaderMode.extract(from: tab.webView) { result in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let message: String
                switch result {
                case .success(let article):
                    ReadingListStore.shared.add(
                        title: article.title,
                        url: tab.webView.url?.absoluteString ?? "",
                        paragraphs: article.paragraphs
                    )
                    message = "Saved to Reading List"
                case .failure:
                    message = "No readable content found on this page"
                }
                let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L.t("done"), style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func translatePage() {
        guard let tab = activeTab, let url = tab.webView.url else { return }
        let language = L.resolvedLanguage.isEmpty ? "en" : L.resolvedLanguage
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+#"))
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) ?? url.absoluteString
        guard let translateURL = URL(string: "https://translate.google.com/translate?sl=auto&tl=\(language)&u=\(encoded)") else { return }
        tab.load(url: translateURL)
    }

    private func lockNow() {
        // Present the auth gate over the top-most controller so the whole app is covered.
        let base = view.window?.rootViewController?.presentedViewController
            ?? view.window?.rootViewController
            ?? self
        guard AppLock.isEnabled else {
            // Lock not enabled: just cover with the manual lock screen.
            let locked = LockedViewController()
            locked.retry = { locked.dismiss(animated: true) }
            locked.modalPresentationStyle = .overFullScreen
            present(locked, animated: false)
            return
        }
        AppLock.gate(viewController: base, reason: "Unlock Magdy Browser", onUnlocked: {})
    }
}
