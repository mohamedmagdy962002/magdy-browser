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
        UserDefaults.standard.set(total + count, forKey: Self.countKey)
        NotificationCenter.default.post(name: .magdyBlockStatsChanged, object: nil)
    }

    /// Runs a page audit: collects resource hosts and matches them against the
    /// domains that the enabled filter lists block.
    func audit(webView: WKWebView) {
        let domains = FilterListManager.shared.blockedDomains
        guard !domains.isEmpty else { return }

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
                guard let url = URL(string: urlString), let host = url.host else { continue }
                for domain in domains where host == domain || host.hasSuffix(".\(domain)") {
                    blocked += 1
                    break
                }
            }
            self.add(blocked)
        }
    }
}

extension Notification.Name {
    static let magdyBlockStatsChanged = Notification.Name("com.magdy.blockStatsChanged")
}
