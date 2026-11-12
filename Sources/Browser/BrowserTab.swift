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

    private var progressObservation: NSKeyValueObservation?

    static let startPage = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
      body{font:-apple-system-body;margin:0;padding:28px;background:#f2f2f7;color:#111}
      h1{font-size:24px;margin:0 0 6px}
      p{color:#555;font-size:15px;margin:0 0 20px}
      a{display:block;padding:14px;background:#fff;border-radius:14px;margin-bottom:10px;
         text-decoration:none;color:#0a84ff;font-weight:600}
      .free{margin-top:24px;color:#8e8e93;font-size:13px}
    </style></head>
    <body>
      <h1>Magdy Browser</h1>
      <p>Free. Unlimited. No account, no subscription, no download caps.</p>
      <a href="https://duckduckgo.com">Search with DuckDuckGo</a>
      <a href="https://www.wikipedia.org">Wikipedia</a>
      <a href="https://github.com">GitHub</a>
      <a href="https://news.ycombinator.com">Hacker News</a>
      <div class="free">Private tabs leave no history behind.</div>
    </body></html>
    """

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

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            guard let self else { return }
            self.onProgress?(self, webView.estimatedProgress)
        }

        loadStartPage()
    }

    func loadStartPage() {
        webView.loadHTMLString(Self.startPage, baseURL: nil)
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
