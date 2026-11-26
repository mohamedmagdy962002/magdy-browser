import Foundation
import WebKit

/// A downloadable media item discovered on a page.
struct MediaCandidate {
    enum Kind: String {
        case video, audio, hls, dash, file

        var label: String {
            switch self {
            case .video: return "Video"
            case .audio: return "Audio"
            case .hls: return "HLS stream"
            case .dash: return "DASH stream"
            case .file: return "File"
            }
        }

        var symbolName: String {
            switch self {
            case .video: return "film"
            case .audio: return "waveform"
            case .hls, .dash: return "dot.radiowaves.left.and.right"
            case .file: return "doc"
            }
        }
    }

    let url: URL
    let title: String
    let kind: Kind
}

/// Finds video/audio sources in a page, including HLS and DASH manifests.
enum MediaScanner {

    static func scan(webView: WKWebView, completion: @escaping ([MediaCandidate]) -> Void) {
        webView.evaluateJavaScript(script) { result, _ in
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let raw = try? JSONDecoder().decode([Raw].self, from: data) else {
                completion([])
                return
            }
            let candidates = raw.compactMap { item -> MediaCandidate? in
                guard let url = URL(string: item.url) else { return nil }
                return MediaCandidate(
                    url: url,
                    title: item.title,
                    kind: MediaCandidate.Kind(rawValue: item.kind) ?? .file
                )
            }
            completion(candidates)
        }
    }

    private struct Raw: Decodable {
        let url: String
        let title: String
        let kind: String
    }

    private static let script = """
    (function () {
      const out = [];
      const seen = new Set();
      const kindOf = (url) => {
        if (/\\.m3u8(\\?|#|$)/i.test(url)) return 'hls';
        if (/\\.mpd(\\?|#|$)/i.test(url)) return 'dash';
        if (/\\.(mp4|m4v|mov|webm|mkv|avi)(\\?|#|$)/i.test(url)) return 'video';
        if (/\\.(mp3|m4a|aac|wav|flac|ogg|opus)(\\?|#|$)/i.test(url)) return 'audio';
        if (/\\.(zip|pdf|apk|epub)(\\?|#|$)/i.test(url)) return 'file';
        return null;
      };
      const add = (url, title, kind) => {
        if (!url) return;
        let absolute;
        try { absolute = new URL(url, document.baseURI).href; } catch (e) { return; }
        if (seen.has(absolute)) return;
        seen.add(absolute);
        out.push({ url: absolute, title: title || absolute, kind: kind });
      };
      document.querySelectorAll('video').forEach((v) => {
        const src = v.currentSrc || v.src || '';
        if (src) add(src, 'video', kindOf(src) || 'video');
        if (v.poster) { /* poster is not a media file */ }
      });
      document.querySelectorAll('video source, audio source, source').forEach((s) => {
        const src = s.src || s.getAttribute('src');
        if (src) add(src, 'source', kindOf(src) || 'video');
      });
      document.querySelectorAll('a[href]').forEach((a) => {
        const href = a.href || '';
        const kind = kindOf(href);
        if (kind) add(href, (a.innerText || '').trim() || href, kind);
      });
      // Manifests referenced by the player configuration.
      try {
        const config = window.__PLAYER_CONFIG__ || window.ytInitialPlayerResponse;
        if (config && config.streamingData) {
          const formats = (config.streamingData.formats || []).concat(config.streamingData.adaptiveFormats || []);
          formats.forEach((f) => {
            const url = f.url || (f.cipher ? null : null);
            if (url) {
              const kind = kindOf(url);
              if (kind) add(url, 'player', kind);
            }
          });
        }
      } catch (e) { }
      return JSON.stringify(out);
    })();
    """
}
