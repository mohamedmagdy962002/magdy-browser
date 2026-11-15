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
    var onProgress: ((BrowserTab, Double) -> Void)?
    /// Fired when the user taps a video element on the page.
    var onVideoTapped: ((URL, String) -> Void)?

    /// Memory Saver: true while the page is released and will reload on activation.
    private(set) var isHibernated = false
    private var hibernatedURL: URL?
    private(set) var lastActivatedAt = Date()
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

    private func applyNewRuleLists() {
        let controller = webView.configuration.userContentController
        let activeIDs = Set(ContentBlocker.shared.ruleLists.map(\.identifier))
        // Detach rule lists that were disabled or replaced since they were applied.
        for (id, list) in appliedRuleLists where !activeIDs.contains(id) {
            controller.remove(list)
            appliedRuleLists.removeValue(forKey: id)
        }
        for list in ContentBlocker.shared.ruleLists where appliedRuleLists[list.identifier] == nil {
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

        // Tapping a video on the page opens the in-app player.
        let videoHook = """
        (function () {
          if (window.__magdyVideoHook) return;
          window.__magdyVideoHook = true;
          document.addEventListener('click', function (event) {
            const target = event.target;
            const video = target && target.tagName === 'VIDEO' ? target : null;
            if (!video) return;
            const src = video.currentSrc || video.src || '';
            if (!src) return;
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

        wireWebView()
        loadStartPage()
    }

    /// Wires the current webView instance — also used after hibernation replaces it.
    private func wireWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        if webView.customUserAgent == nil {
            webView.customUserAgent = "MagdyBrowser/1.0"
        }
        // Newly compiled filter lists are attached to this tab as they arrive.
        blockerObserver = ContentBlocker.shared.observe { [weak self] in
            self?.applyNewRuleLists()
        }
        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self else { return }
            self.onProgress?(self, webView.estimatedProgress)
        }
    }

    // MARK: - Hibernation (Memory Saver)

    /// Releases the live page to free memory. Private tabs are never hibernated.
    func hibernate() {
        guard !isPrivate, !isHibernated else { return }
        isHibernated = true
        // Only the CURRENT page is restored — a tab parked on the start page wakes to the start page.
        hibernatedURL = webView.url
        let frame = webView.frame
        let userAgent = webView.customUserAgent
        if let blockerObserver {
            ContentBlocker.shared.removeObserver(blockerObserver)
            self.blockerObserver = nil
        }
        progressObservation = nil
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
        // Documents is the base URL so the wallpaper resolves as a relative resource.
        webView.loadHTMLString(SpeedDialPage.html(), baseURL: WallpaperStore.shared.documentsURL)
    }

    func load(url: URL) {
        applyRememberedUserAgent(for: url)
        webView.load(URLRequest(url: url))
    }

    func reload() {
        if webView.url?.absoluteString == nil { loadStartPage() } else { webView.reload() }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func stopLoading() { webView.stopLoading() }
}

// MARK: - Navigation

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onLoadingChange?(self, true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadingChange?(self, false)
        if let pageTitle = webView.title, !pageTitle.isEmpty, pageTitle != title {
            title = pageTitle
            onTitleChange?(self)
        }
        // Private tabs leave no trace on the device.
        if !isPrivate, let url = webView.url {
            HistoryStore.shared.record(url: url, title: webView.title)
        }
        if !isPrivate {
            BlockStats.shared.audit(webView: webView)
        }
        applyNightModeIfNeeded()
        detectRSSFeeds()
    }

    /// Reads the page's advertised RSS/Atom links so the menu can offer them.
    private func detectRSSFeeds() {
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
                  let json = result as? String,
                  let data = json.data(using: .utf8),
                  let feeds = try? JSONDecoder().decode([String].self, from: data) else { return }
            self.rssFeeds = feeds
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // Old page's feeds must not leak into the new one's menu.
        rssFeeds = []
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadingChange?(self, false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadingChange?(self, false)
        if (error as NSError).code == NSURLErrorCancelled { return }
        let host = webView.url?.host ?? webView.backForwardList.currentItem?.url.host ?? "page"
        webView.loadHTMLString(Self.errorPage(host: host), baseURL: nil)
    }

    private static func errorPage(host: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font-family:-apple-system,system-ui,sans-serif;background:#F5F5FB;color:#1C1C1E;
        display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
        .card{background:#fff;border-radius:20px;padding:36px 30px;max-width:320px;text-align:center;
        box-shadow:0 8px 24px rgba(28,28,30,.08)}
        h1{font-size:20px;margin:0 0 8px}p{color:#8E8E93;font-size:14px;margin:0 0 20px}
        button{background:#4A47F0;color:#fff;border:0;border-radius:14px;padding:12px 28px;
        font-size:15px;font-weight:700}</style></head>
        <body><div class="card"><h1>\(host) is unreachable</h1>
        <p>Check the address or your connection.</p>
        <button onclick="location.reload()">Try Again</button></div></body></html>
        """
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
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
        DownloadManager.shared.attach(download: download, url: navigationAction.request.url)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        DownloadManager.shared.attach(download: download, url: navigationResponse.response.url)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // target="_blank" links stay in this tab instead of opening a dead window.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
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
        // Show real alerts — silently swallowing them hides page errors.
        let alert = UIAlertController(title: webView.title ?? webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presentingViewController()?.present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // Real confirm — auto-answering OK would fire destructive actions on pages.
        let alert = UIAlertController(title: webView.title ?? webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        presentingViewController()?.present(alert, animated: true)
    }

    // Camera / mic / motion sensors: pages get the system prompt automatically.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.prompt)
    }

    /// Long-press on a link: open in new tab, copy, download.
    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping (UIContextMenuConfiguration?) -> Void
    ) {
        guard let url = elementInfo.linkURL else {
            completionHandler(nil)
            return
        }
        let config = UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { _ in
                    NotificationCenter.default.post(name: .magdyOpenURL, object: url)
                },
                UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = url.absoluteString
                },
                UIAction(title: "Download", image: UIImage(systemName: "arrow.down.circle")) { [weak self] _ in
                    guard let self else { return }
                    self.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                        DownloadManager.shared.start(url: url, referer: self.webView.url, cookies: cookies)
                    }
                }
            ])
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

    /// Applies the global text zoom (50–200%) chosen in settings.
    func applyTextZoomIfNeeded() {
        let zoom = UserDefaults.standard.object(forKey: BrowserTab.textZoomKey) as? Double ?? 100
        guard zoom != 100 else { return }
        webView.evaluateJavaScript(
            "document.body.style.webkitTextSizeAdjust='\(Int(zoom))%';",
            completionHandler: nil
        )
    }

    static let textZoomKey = "magdy.textZoom"

    /// Applies the remembered per-site user agent (desktop/mobile) for the host.
    func applyRememberedUserAgent(for url: URL?) {
        guard let host = url?.host else { return }
        let perSite = UserDefaults.standard.dictionary(forKey: "magdy.uaPerSite") as? [String: String] ?? [:]
        if perSite[host] == "desktop" {
            webView.customUserAgent = Self.desktopUserAgent
        } else {
            webView.customUserAgent = "MagdyBrowser/1.0"
        }
    }

    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    static func rememberUserAgent(host: String, desktop: Bool) {
        var perSite = UserDefaults.standard.dictionary(forKey: "magdy.uaPerSite") as? [String: String] ?? [:]
        perSite[host] = desktop ? "desktop" : "mobile"
        UserDefaults.standard.set(perSite, forKey: "magdy.uaPerSite")
    }
}

// MARK: - Script messages

extension BrowserTab: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "magdyVideo",
              let payload = message.body as? [String: Any],
              let urlString = payload["url"] as? String,
              let url = URL(string: urlString) else { return }
        let title = payload["title"] as? String ?? ""
        DispatchQueue.main.async { [weak self] in
            self?.onVideoTapped?(url, title)
        }
    }
}
