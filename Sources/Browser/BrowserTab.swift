import UIKit
import WebKit

/// One browser tab: owns its web view, its privacy mode and its navigation state.
final class BrowserTab: NSObject {
    let id = UUID()
    let isPrivate: Bool
    private(set) var webView: WKWebView

    private(set) var title: String = "New Tab"

    var onTitleChange: ((BrowserTab) -> Void)?
    var onLoadingChange: ((BrowserTab, Bool) -> Void)?
    var onPresentationChange: ((BrowserTab) -> Void)?
    var onProgress: ((BrowserTab, Double) -> Void)?
    /// Fired when the user taps a video element on the page.
    var onVideoTapped: ((URL, String) -> Void)?
    /// Long-pressed a link → (url, wants private tab).
    var onOpenLink: ((URL, Bool) -> Void)?
    /// Start-page quick action button: "private" | "qr" | "voice" | "downloads" | "search".
    var onQuickAction: ((String) -> Void)?
    var onPresentAlert: ((UIAlertController) -> Bool)?
    var onSessionURLChange: ((BrowserTab) -> Void)?

    private var privateTextZooms: [String: Double] = [:]
    private var privateUserAgents: [String: String] = [:]
    private var privateAdAllowedHosts: Set<String> = []

    /// Memory Saver: true while the page is released and will reload on activation.
    private(set) var isHibernated = false
    private var hibernatedURL: URL?
    private var failedURL: URL?
    private var pendingURL: URL?
    private var isLoadingErrorPage = false
    private var isLoadingStartPage = false
    private weak var activeNavigation: WKNavigation?
    private weak var generatedNavigation: WKNavigation?
    private var navigationID = UUID()
    var lastActivatedAt = Date()
    /// RSS/Atom feeds advertised by the current page (set on finish loading).
    private(set) var rssFeeds: [String] = []

    private var progressObservation: NSKeyValueObservation?
    private var blockerObserver: UUID?
    private var appliedRuleLists: [String: WKContentRuleList] = [:]
    /// The shared per-tab configuration — user scripts and message handlers
    /// registered here carry over to any replacement web view.
    private let baseConfiguration: WKWebViewConfiguration

    deinit {
        if let blockerObserver {
            ContentBlocker.shared.removeObserver(blockerObserver)
        }
    }

    /// URL shown in chrome when the tab may be hibernated.
    var displayURL: URL? {
        webView.url ?? hibernatedURL
    }

    var sessionURL: URL? {
        guard failedURL == nil, let url = displayURL, url.isWebURL else { return nil }
        return url
    }

    var isStartPage: Bool {
        failedURL == nil && displayURL?.isWebURL != true
    }

    var isPresentingStartPage: Bool {
        failedURL == nil && pendingURL == nil && displayURL?.isWebURL != true
    }

    // MARK: - Per-site ad allowlist

    static func isAdBlockingRuleList(_ identifier: String) -> Bool {
        [
            "MagdyBlockList.ads",
            "MagdyFilter.easylist",
            "MagdyFilter.easylist_germany",
            "MagdyFilter.fanboy_annoyance",
            "MagdyFilter.fanboy_social",
            "MagdyFilter.peter_lowe"
        ].contains(identifier)
    }

    /// True when the user exempted this host from ad blocking.
    static func isAdAllowed(_ host: String?) -> Bool {
        guard let host else { return false }
        let allowed = UserDefaults.standard.stringArray(forKey: "magdy.adAllowedSites") ?? []
        return allowed.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func setAdAllowed(_ host: String, _ allowed: Bool) {
        var hosts = UserDefaults.standard.stringArray(forKey: "magdy.adAllowedSites") ?? []
        hosts.removeAll { $0 == host }
        if allowed { hosts.append(host) }
        UserDefaults.standard.set(hosts, forKey: "magdy.adAllowedSites")
    }

    func isAdAllowed(_ host: String?) -> Bool {
        guard let host else { return false }
        if isPrivate {
            return privateAdAllowedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        }
        return Self.isAdAllowed(host)
    }

    func setAdAllowed(_ allowed: Bool, for host: String) {
        if isPrivate {
            if allowed {
                privateAdAllowedHosts.insert(host)
            } else {
                privateAdAllowedHosts.remove(host)
            }
        } else {
            Self.setAdAllowed(host, allowed)
        }
    }

    func applyNewRuleLists() {
        let controller = webView.configuration.userContentController
        let allowsAds = isAdAllowed(webView.url?.host)
        let activeIDs = Set(ContentBlocker.shared.ruleLists.map(\.identifier))
            .filter { !allowsAds || !Self.isAdBlockingRuleList($0) }
        for (id, list) in appliedRuleLists where !activeIDs.contains(id) {
            controller.remove(list)
            appliedRuleLists.removeValue(forKey: id)
        }
        for list in ContentBlocker.shared.ruleLists
            where activeIDs.contains(list.identifier) && appliedRuleLists[list.identifier] == nil {
            appliedRuleLists[list.identifier] = list
            controller.add(list)
        }
    }

    init(isPrivate: Bool) {
        self.isPrivate = isPrivate

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = isPrivate ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore.default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.suppressesIncrementalRendering = false

        self.baseConfiguration = configuration
        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        ContentBlocker.shared.apply(to: configuration.userContentController)
        appliedRuleLists = Dictionary(
            ContentBlocker.shared.ruleLists.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Tapping a video on the page opens the in-app player instead of the
        // native fullscreen player. Also forces playsinline on every video —
        // without it iPhone plays fullscreen natively and ignores our hook.
        let videoHook = """
        (function () {
          if (window.__magdyVideoHook) return;
          window.__magdyVideoHook = true;
          function forceInline(v) {
            v.setAttribute('playsinline', '');
            v.setAttribute('webkit-playsinline', '');
          }
          function ensurePill() {
            if (document.getElementById('magdyPlayerPill')) return;
            if (!document.querySelector('video')) return;
            var btn = document.createElement('button');
            btn.id = 'magdyPlayerPill';
            btn.textContent = '▶ Player';
            btn.style.cssText = 'position:fixed;bottom:76px;right:14px;z-index:2147483647;padding:10px 16px;border:none;border-radius:22px;background:linear-gradient(135deg,#8B5CF6,#A78BFA);color:#fff;font:600 13px -apple-system;box-shadow:0 6px 18px rgba(0,0,0,.35);';
            btn.addEventListener('click', function (ev) {
              ev.preventDefault();
              ev.stopPropagation();
              var v = document.querySelector('video');
              var src = v ? (v.currentSrc || v.src || (v.querySelector('source') && v.querySelector('source').src) || '') : '';
              if (src && !/^https?:/i.test(src) && window.webkit.messageHandlers.magdyAction) {
                window.webkit.messageHandlers.magdyAction.postMessage('unsupported-video');
                return;
              }
              if (src && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.magdyVideo) {
                window.webkit.messageHandlers.magdyVideo.postMessage({ url: src, title: document.title || '' });
              }
            });
            document.documentElement.appendChild(btn);
          }
          document.querySelectorAll('video').forEach(forceInline);
          ensurePill();
          new MutationObserver(function (mutations) {
            mutations.forEach(function (m) {
              m.addedNodes.forEach(function (n) {
                if (n.tagName === 'VIDEO') forceInline(n);
                if (n.querySelectorAll) n.querySelectorAll('video').forEach(forceInline);
              });
            });
            ensurePill();
          }).observe(document.documentElement, { childList: true, subtree: true });
          document.addEventListener('click', function (event) {
            const target = event.target;
            const video = target && target.closest ? target.closest('video') : null;
            if (!video) return;
            event.preventDefault();
            event.stopPropagation();
            const source = video.querySelector('source');
            const src = video.currentSrc || video.src || (source && source.src) || '';
            if (!src) return;
            if (!/^https?:/i.test(src) && window.webkit.messageHandlers.magdyAction) {
              window.webkit.messageHandlers.magdyAction.postMessage('unsupported-video');
              return;
            }
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.magdyVideo) {
              window.webkit.messageHandlers.magdyVideo.postMessage({
                url: src, title: document.title || ''
              });
            }
          }, true);
        })();
        """
        let source = WKUserScript(source: videoHook, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(source)
        configuration.userContentController.add(WeakScriptMessageProxy(target: self), name: "magdyVideo")
        configuration.userContentController.add(WeakScriptMessageProxy(target: self), name: "magdyAction")
        // Force Zoom: rewrite the viewport so pinch-zoom works on pages that block it.
        if UserDefaults.standard.bool(forKey: "magdy.forceZoom") {
            let script = WKUserScript(
                source: """
                (function(){
                  var m=document.querySelector('meta[name=viewport]');
                  if(m){m.setAttribute('content','width=device-width, initial-scale=1, maximum-scale=10, minimum-scale=0.2, user-scalable=yes');}
                })();
                """,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            configuration.userContentController.addUserScript(script)
        }

        wireWebView()
        loadStartPage()
    }

    /// Wires the current webView instance — also used after hibernation replaces it.
    private func wireWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // No custom UA by default — WebKit's native Mobile Safari UA is what
        // makes sites serve mobile layouts. Only remembered desktop sites override.
        // Newly compiled filter lists are attached to this tab as they arrive.
        blockerObserver = ContentBlocker.shared.observe { [weak self] in
            self?.applyNewRuleLists()
        }
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self, webView === self.webView else { return }
            self.onProgress?(self, webView.estimatedProgress)
        }
    }

    // MARK: - Hibernation (Memory Saver)

    /// Releases the live page to free memory. Private tabs are never hibernated.
    func hibernate() {
        guard !isPrivate, !isHibernated else { return }
        isHibernated = true
        // Only web pages are restored; a tab parked on the start page wakes to a fresh start page.
        hibernatedURL = webView.url?.isWebURL == true ? webView.url : nil
        let frame = webView.frame
        let userAgent = webView.customUserAgent
        let previousWebView = webView
        previousWebView.navigationDelegate = nil
        previousWebView.uiDelegate = nil
        previousWebView.scrollView.delegate = nil
        previousWebView.stopLoading()
        previousWebView.removeFromSuperview()
        if let blockerObserver {
            ContentBlocker.shared.removeObserver(blockerObserver)
            self.blockerObserver = nil
        }
        progressObservation = nil
        activeNavigation = nil
        generatedNavigation = nil
        navigationID = UUID()
        pendingURL = nil
        isLoadingErrorPage = false
        isLoadingStartPage = false
        onLoadingChange?(self, false)
        onPresentationChange?(self)
        // The replacement webView reuses baseConfiguration, whose userContentController
        // already carries every rule list — do NOT reset appliedRuleLists (double-attach).
        webView = WKWebView(frame: frame, configuration: baseConfiguration)
        webView.customUserAgent = userAgent
        wireWebView()
    }

    /// Reloads the hibernated page.
    func wake() {
        guard isHibernated else { return }
        isHibernated = false
        lastActivatedAt = Date()
        // The replacement webView's controller is a copy of the base one — reset
        // tracking and re-attach every active rule list so none compiled after
        // init is missing from the fresh copy.
        let controller = webView.configuration.userContentController
        for (_, list) in appliedRuleLists { controller.remove(list) }
        appliedRuleLists = [:]
        applyNewRuleLists()
        if let url = hibernatedURL {
            hibernatedURL = nil
            load(url: url)
        } else {
            loadStartPage()
        }
    }

    func loadStartPage() {
        failedURL = nil
        pendingURL = nil
        activeNavigation = nil
        generatedNavigation = nil
        navigationID = UUID()
        isLoadingErrorPage = false
        isLoadingStartPage = true
        onPresentationChange?(self)
        // Documents is the base URL so the wallpaper resolves as a relative resource.
        let navigation = webView.loadHTMLString(
            SpeedDialPage.html(includeHistory: !isPrivate),
            baseURL: WallpaperStore.shared.documentsURL
        )
        activeNavigation = navigation
        generatedNavigation = navigation
    }

    func load(url: URL) {
        guard url.isWebURL else { return }
        failedURL = nil
        pendingURL = url
        activeNavigation = nil
        generatedNavigation = nil
        navigationID = UUID()
        isLoadingErrorPage = false
        isLoadingStartPage = false
        onPresentationChange?(self)
        applyRememberedUserAgent(for: url)
        activeNavigation = webView.load(URLRequest(url: url))
    }

    func reload() {
        if let failedURL {
            load(url: failedURL)
        } else if displayURL?.isWebURL == true {
            generatedNavigation = nil
            navigationID = UUID()
            isLoadingErrorPage = false
            isLoadingStartPage = false
            activeNavigation = webView.reload()
        } else {
            loadStartPage()
        }
    }

    private func retryLastFailure() {
        guard let failedURL else {
            loadStartPage()
            return
        }
        load(url: failedURL)
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func stopLoading() {
        webView.stopLoading()
        activeNavigation = nil
        generatedNavigation = nil
        navigationID = UUID()
        pendingURL = nil
        isLoadingErrorPage = false
        isLoadingStartPage = false
        onLoadingChange?(self, false)
        onPresentationChange?(self)
    }
}

// MARK: - Navigation

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        let isGeneratedNavigation = generatedNavigation === navigation
            || (activeNavigation === navigation && (isLoadingStartPage || isLoadingErrorPage))
        activeNavigation = navigation
        navigationID = UUID()
        if !isGeneratedNavigation {
            generatedNavigation = nil
            isLoadingErrorPage = false
            isLoadingStartPage = false
        }
        onLoadingChange?(self, true)
        onPresentationChange?(self)
        // Old page's feeds must not leak into the new one's menu.
        rssFeeds = []
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView === self.webView, activeNavigation === navigation else { return }
        if isLoadingErrorPage { return }
        isLoadingStartPage = false
        failedURL = nil
        pendingURL = webView.url
        onPresentationChange?(self)
        // Host is final here — re-evaluate the per-site ad allowlist for this navigation.
        applyNewRuleLists()
        if !isPrivate, let url = webView.url, url.isWebURL {
            onSessionURLChange?(self)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, activeNavigation === navigation else { return }
        onLoadingChange?(self, false)
        if isLoadingErrorPage {
            isLoadingErrorPage = false
            isLoadingStartPage = false
            pendingURL = nil
            activeNavigation = nil
            generatedNavigation = nil
            onPresentationChange?(self)
            return
        }
        isLoadingStartPage = false
        failedURL = nil
        pendingURL = nil
        if let pageTitle = webView.title, !pageTitle.isEmpty, pageTitle != title {
            title = pageTitle
            onTitleChange?(self)
        }
        // Private tabs leave no trace; generated start/error pages are not history.
        if !isPrivate, let url = webView.url, url.isWebURL {
            HistoryStore.shared.record(url: url, title: webView.title)
            onSessionURLChange?(self)
        }
        if !isPrivate {
            BlockStats.shared.audit(webView: webView)
        }
        applyNightModeIfNeeded()
        detectRSSFeeds(in: webView, navigationID: navigationID)
        activeNavigation = nil
        generatedNavigation = nil
        onPresentationChange?(self)
    }

    /// Reads the page's advertised RSS/Atom links so the menu can offer them.
    private func detectRSSFeeds(in webView: WKWebView, navigationID: UUID) {
        let script = """
        (function () {
          const feeds = [];
          document.querySelectorAll('link[type*="rss"], link[type*="atom"]').forEach(function (link) {
            if (link.href) feeds.push(link.href);
          });
          return JSON.stringify(feeds);
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self,
                  webView === self.webView,
                  self.navigationID == navigationID,
                  let json = result as? String,
                  let data = json.data(using: .utf8),
                  let feeds = try? JSONDecoder().decode([String].self, from: data) else { return }
            self.rssFeeds = feeds
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView, activeNavigation === navigation else { return }
        onLoadingChange?(self, false)
        if (error as NSError).code == NSURLErrorCancelled {
            activeNavigation = nil
            generatedNavigation = nil
            navigationID = UUID()
            pendingURL = nil
            isLoadingErrorPage = false
            isLoadingStartPage = false
            onPresentationChange?(self)
            return
        }
        showLoadError(in: webView)
        onPresentationChange?(self)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView, activeNavigation === navigation else { return }
        onLoadingChange?(self, false)
        if (error as NSError).code == NSURLErrorCancelled {
            activeNavigation = nil
            generatedNavigation = nil
            navigationID = UUID()
            pendingURL = nil
            isLoadingErrorPage = false
            isLoadingStartPage = false
            onPresentationChange?(self)
            return
        }
        showLoadError(in: webView)
        onPresentationChange?(self)
    }

    private func showLoadError(in webView: WKWebView) {
        guard !isLoadingErrorPage else { return }
        if let pendingURL, pendingURL.isWebURL {
            failedURL = pendingURL
        } else if let current = webView.url, current.isWebURL {
            failedURL = current
        }
        let host = failedURL?.host ?? "This page"
        activeNavigation = nil
        generatedNavigation = nil
        navigationID = UUID()
        pendingURL = nil
        isLoadingStartPage = false
        isLoadingErrorPage = true
        let errorNavigation = webView.loadHTMLString(
            Self.errorPage(host: host),
            baseURL: WallpaperStore.shared.documentsURL
        )
        activeNavigation = errorNavigation
        generatedNavigation = errorNavigation
    }

    private static func errorPage(host: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>body{font-family:-apple-system,system-ui,sans-serif;background:#FBF8FF;color:#1B1B21;
        display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:24px;box-sizing:border-box}
        .card{background:#fff;border:1px solid rgba(201,196,213,.55);border-radius:20px;padding:36px 30px;max-width:340px;text-align:center;
        box-shadow:0 8px 24px rgba(27,27,33,.08)}
        h1{font-size:20px;margin:0 0 8px}p{color:#484553;font-size:14px;line-height:1.5;margin:0 0 20px}
        button{background:#5F48BD;color:#fff;border:0;border-radius:12px;padding:12px 28px;
        font-size:15px;font-weight:700;min-height:44px}
        @media(prefers-color-scheme:dark){body{background:#0D0E12;color:#F3F4F6}.card{background:#181920;border-color:#262734;
        box-shadow:0 8px 24px rgba(0,0,0,.35)}p{color:#9CA3AF}button{background:#8B5CF6}}</style></head>
        <body><div class="card"><h1>\(escapeHTML(host)) is unreachable</h1>
        <p>Check the address or your connection.</p>
        <button onclick="webkit.messageHandlers.magdyAction.postMessage('retry')">Try Again</button></div></body></html>
        """
    }

    private static func escapeHTML(_ text: String) -> String {
        SpeedDialPage.escape(text)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard webView === self.webView else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if navigationAction.targetFrame?.isMainFrame != false,
           let url = navigationAction.request.url,
           url.isWebURL {
            pendingURL = url
        }
        if navigationAction.targetFrame?.isMainFrame != false,
           let url = navigationAction.request.url,
           !url.isWebURL {
            let scheme = url.scheme?.lowercased()
            let isGeneratedBase = url.standardizedFileURL == WallpaperStore.shared.documentsURL.standardizedFileURL
            let isGeneratedPage = scheme == "about"
                || (scheme == "file" && isGeneratedBase && (isLoadingStartPage || isLoadingErrorPage))
            guard isGeneratedPage else {
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }
}

// MARK: - UI delegate

extension BrowserTab: WKUIDelegate {
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        guard webView === self.webView else { return }
        DownloadManager.shared.attach(download: download, url: navigationAction.request.url)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        guard webView === self.webView else { return }
        DownloadManager.shared.attach(download: download, url: navigationResponse.response.url)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // target="_blank" links stay in this tab instead of opening a dead window.
        if webView === self.webView, navigationAction.targetFrame == nil,
           let url = navigationAction.request.url {
            load(url: url)
        }
        return nil
    }

    /// BrowserTab is not a view controller — resolve the top-most one to present page dialogs.
    private func presentingViewController() -> UIViewController? {
        var top = webView.window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: webView.title ?? webView.url?.host, message: message, preferredStyle: .alert)
        var completed = false
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            guard !completed else { return }
            completed = true
            completionHandler()
        })
        if let presenter = presentingViewController(), presenter.presentedViewController == nil {
            presenter.present(alert, animated: true)
        } else if onPresentAlert?(alert) != true {
            completed = true
            completionHandler()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: webView.title ?? webView.url?.host, message: message, preferredStyle: .alert)
        var completed = false
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            guard !completed else { return }
            completed = true
            completionHandler(true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            guard !completed else { return }
            completed = true
            completionHandler(false)
        })
        if let presenter = presentingViewController(), presenter.presentedViewController == nil {
            presenter.present(alert, animated: true)
        } else if onPresentAlert?(alert) != true {
            completed = true
            completionHandler(false)
        }
    }

    // Camera / mic / motion sensors: pages get the system prompt automatically.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.prompt)
    }

    /// Long-press on a link: open in new tab, private tab, Safari, copy, download.
    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
    ) {
        guard let url = elementInfo.linkURL else {
            completionHandler(nil)
            return
        }
        let config = UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            var actions: [UIMenuElement] = [
                UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
                    self?.onOpenLink?(url, self?.isPrivate == true)
                },
                UIAction(title: "Open in Private Tab", image: UIImage(systemName: "eye.slash")) { _ in
                    self?.onOpenLink?(url, true)
                }
            ]
            let mediaExts = ["mp4", "m3u8", "webm", "mov", "mkv", "m4v", "avi", "ts", "mpd"]
            if mediaExts.contains(url.pathExtension.lowercased()) {
                actions.append(
                    UIAction(title: "Open in Video Player", image: UIImage(systemName: "play.rectangle")) { [weak self] _ in
                        self?.onVideoTapped?(url, url.lastPathComponent)
                    }
                )
            }
            actions.append(contentsOf: [
                UIAction(title: "Open in Safari", image: UIImage(systemName: "safari")) { _ in
                    UIApplication.shared.open(url)
                },
                UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = url.absoluteString
                },
                UIAction(title: "Download", image: UIImage(systemName: "arrow.down.circle")) { [weak self] _ in
                    guard let self else { return }
                    self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        DispatchQueue.main.async {
                            guard let presenter = self.presentingViewController() else { return }
                            DownloadOptionsSheet.present(
                                url: url, referer: self.webView.url, cookies: cookies,
                                presenter: presenter
                            )
                        }
                    }
                }
            ])
            return UIMenu(children: actions)
        })
        completionHandler(config)
    }
}

// MARK: - Page tools

extension BrowserTab {
    /// Renders the page to a PDF via the system print pipeline (works on all iOS versions).
    func exportPDF(fullPage: Bool, completion: @escaping (URL?) -> Void) {
        let printFormatter = webView.viewPrintFormatter()
        let pageRenderer = UIPrintPageRenderer()
        pageRenderer.addPrintFormatter(printFormatter, startingAtPageAt: 0)
        let paper = CGRect(x: 0, y: 0, width: 595, height: 841)
        pageRenderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        pageRenderer.setValue(NSValue(cgRect: paper.insetBy(dx: 24, dy: 24)), forKey: "printableRect")

        let renderer = UIGraphicsPDFRenderer(bounds: paper)
        let data = renderer.pdfData { context in
            for page in 0..<pageRenderer.numberOfPages {
                context.beginPage()
                pageRenderer.drawPage(at: page, in: context.pdfContextBounds)
            }
        }
        guard !data.isEmpty else {
            completion(nil)
            return
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var name = (webView.title ?? "page")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        if name.isEmpty { name = "page" }
        let url = docs.appendingPathComponent("\(name)-\(Int(Date().timeIntervalSince1970)).pdf")
        do {
            try data.write(to: url)
            completion(url)
        } catch {
            completion(nil)
        }
    }

    /// Injects or removes the night-mode CSS filter on the live page.
    func setNightMode(_ enabled: Bool) {
        let js = enabled
            ? """
            (function(){let s=document.getElementById('magdy-night');if(!s){s=document.createElement('style');
            s.id='magdy-night';s.textContent='html{filter:invert(1) hue-rotate(180deg)!important;background:#000!important}'+
            'img,video,iframe{filter:invert(1) hue-rotate(180deg)!important}';document.head.appendChild(s);}})()
            """
            : "(function(){let s=document.getElementById('magdy-night');if(s)s.remove();})()"
        webView.evaluateJavaScript(js, completionHandler: nil)
        nightModeEnabled = enabled
    }

    var nightModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "magdy.nightMode") }
        set { UserDefaults.standard.set(newValue, forKey: "magdy.nightMode") }
    }

    /// Applies night mode to a freshly loaded page if the toggle is on.
    func applyNightModeIfNeeded() {
        if nightModeEnabled {
            setNightMode(true)
        }
        applyTextZoomIfNeeded()
    }

    /// Applies the page's text zoom: per-site choice wins over the global setting.
    func applyTextZoomIfNeeded() {
        let zoom = effectiveTextZoom()
        guard zoom != 100 else { return }
        webView.evaluateJavaScript(
            "document.body.style.webkitTextSizeAdjust='\(Int(zoom))%';",
            completionHandler: nil
        )
    }

    /// Effective zoom (50–200%): per-site override, else the global setting.
    func effectiveTextZoom() -> Double {
        if let host = webView.url?.host {
            if isPrivate, let site = privateTextZooms[host] { return site }
            if !isPrivate {
                let perSite = UserDefaults.standard.dictionary(forKey: "magdy.zoomPerSite") as? [String: Double] ?? [:]
                if let site = perSite[host] { return site }
            }
        }
        return UserDefaults.standard.object(forKey: BrowserTab.textZoomKey) as? Double ?? 100
    }

    func setSiteZoom(_ zoom: Double?, for host: String) {
        if isPrivate {
            if let zoom {
                privateTextZooms[host] = zoom
            } else {
                privateTextZooms.removeValue(forKey: host)
            }
        } else {
            Self.setSiteZoom(zoom, for: host)
        }
    }

    /// Remembers (or clears, when nil) a per-host zoom.
    static func setSiteZoom(_ zoom: Double?, for host: String) {
        var perSite = UserDefaults.standard.dictionary(forKey: "magdy.zoomPerSite") as? [String: Double] ?? [:]
        if let zoom {
            perSite[host] = zoom
        } else {
            perSite.removeValue(forKey: host)
        }
        UserDefaults.standard.set(perSite, forKey: "magdy.zoomPerSite")
    }

    static let textZoomKey = "magdy.textZoom"

    /// Applies the remembered per-site user agent (desktop/mobile) for the host.
    func applyRememberedUserAgent(for url: URL?) {
        guard let host = url?.host else { return }
        if isPrivate {
            webView.customUserAgent = privateUserAgents[host] == "desktop" ? Self.desktopUserAgent : nil
            return
        }
        let perSite = UserDefaults.standard.dictionary(forKey: "magdy.uaPerSite") as? [String: String] ?? [:]
        if perSite[host] == "desktop" {
            webView.customUserAgent = Self.desktopUserAgent
        } else {
            // Unremembered or mobile sites: system default (proper Mobile Safari UA).
            webView.customUserAgent = nil
        }
    }

    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    static func rememberUserAgent(host: String, desktop: Bool) {
        var perSite = UserDefaults.standard.dictionary(forKey: "magdy.uaPerSite") as? [String: String] ?? [:]
        perSite[host] = desktop ? "desktop" : "mobile"
        UserDefaults.standard.set(perSite, forKey: "magdy.uaPerSite")
    }

    func rememberUserAgent(desktop: Bool, for host: String) {
        if isPrivate {
            privateUserAgents[host] = desktop ? "desktop" : "mobile"
        } else {
            Self.rememberUserAgent(host: host, desktop: desktop)
        }
    }
}

// MARK: - Script messages

extension BrowserTab: WKScriptMessageHandler {
    private func frameIsMainDocument(_ frame: WKFrameInfo) -> Bool {
        frame.isMainFrame && frame.request.url?.isWebURL == true
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == "magdyAction", let action = message.body as? String {
            guard message.frameInfo.isMainFrame else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if action == "retry" {
                    self.retryLastFailure()
                } else {
                    self.onQuickAction?(action)
                }
            }
            return
        }
        guard message.name == "magdyVideo",
              frameIsMainDocument(message.frameInfo),
              let payload = message.body as? [String: Any],
              let urlString = payload["url"] as? String,
              let url = URL(string: urlString), url.isWebURL else { return }
        let title = payload["title"] as? String ?? ""
        DispatchQueue.main.async { [weak self] in
            self?.onVideoTapped?(url, title)
        }
    }
}
