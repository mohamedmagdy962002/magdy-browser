import UIKit
import WebKit

/// One browser tab: owns its web view, its privacy mode and its navigation state.
final class BrowserTab: NSObject {
    let id = UUID()
    let isPrivate: Bool
    let webView: WKWebView

    private(set) var title: String = "New Tab"

    var onTitleChange: ((BrowserTab) -> Void)?
    var onLoadingChange: ((BrowserTab, Bool) -> Void)?
    var onProgress: ((BrowserTab, Double) -> Void)?
    /// Fired when the user taps a video element on the page.
    var onVideoTapped: ((URL, String) -> Void)?

    private var progressObservation: NSKeyValueObservation?
    private var blockerObserver: UUID?
    private var appliedRuleListIDs: Set<String> = []

    deinit {
        if let blockerObserver {
            ContentBlocker.shared.removeObserver(blockerObserver)
        }
    }

    private func applyNewRuleLists() {
        for list in ContentBlocker.shared.ruleLists where !appliedRuleListIDs.contains(list.identifier) {
            appliedRuleListIDs.insert(list.identifier)
            webView.configuration.userContentController.add(list)
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

        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "MagdyBrowser/1.0"

        ContentBlocker.shared.apply(to: configuration.userContentController)
        appliedRuleListIDs = Set(ContentBlocker.shared.ruleLists.map(\.identifier))

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

        // Newly compiled filter lists are attached to this tab as they arrive.
        blockerObserver = ContentBlocker.shared.observe { [weak self] in
            self?.applyNewRuleLists()
        }

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self else { return }
            self.onProgress?(self, webView.estimatedProgress)
        }

        loadStartPage()
    }

    func loadStartPage() {
        // Documents is the base URL so the wallpaper resolves as a relative resource.
        webView.loadHTMLString(SpeedDialPage.html(), baseURL: WallpaperStore.shared.documentsURL)
    }

    func load(url: URL) {
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
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadingChange?(self, false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadingChange?(self, false)
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

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
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
