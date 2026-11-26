import Foundation
import WebKit

/// Cumulative "ads blocked" counter, fed by a page audit at load finish.
final class BlockStats {
    static let shared = BlockStats()

    static let countKey = "magdy.blockStats.count"

    var total: Int {
        UserDefaults.standard.integer(forKey: Self.countKey)
    }

    func add(_ count: Int) {
        guard count > 0 else { return }
        let current = max(0, total)
        let result = current.addingReportingOverflow(count)
        UserDefaults.standard.set(result.overflow ? Int.max : result.partialValue, forKey: Self.countKey)
        NotificationCenter.default.post(name: .magdyBlockStatsChanged, object: nil)
    }

    /// Runs a page audit: collects resource hosts and matches them against the
    /// domains that the enabled filter lists block.
    func audit(webView: WKWebView) {
        let manager = FilterListManager.shared
        let blockedDomains = manager.blockedDomains
        let exceptionDomains = manager.exceptionDomains
        guard !blockedDomains.isEmpty else { return }

        let script = """
        (function () {
          const urls = [];
          document.querySelectorAll('img,iframe,script,source,video,audio,link').forEach((el) => {
            const src = el.src || el.href || '';
            if (src) urls.push(src);
          });
          return JSON.stringify(urls);
        })();
        """
        webView.evaluateJavaScript(script) { result, _ in
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let urls = try? JSONDecoder().decode([String].self, from: data) else { return }

            var blocked = 0
            for urlString in urls {
                guard let url = URL(string: urlString), let host = url.host?.lowercased() else { continue }
                func matches(_ domain: String) -> Bool {
                    host == domain || host.hasSuffix(".\(domain)")
                }
                if !exceptionDomains.contains(where: matches), blockedDomains.contains(where: matches) {
                    blocked += 1
                }
            }
            self.add(blocked)
        }
    }
}

extension Notification.Name {
    static let magdyBlockStatsChanged = Notification.Name("com.magdy.blockStatsChanged")
}
