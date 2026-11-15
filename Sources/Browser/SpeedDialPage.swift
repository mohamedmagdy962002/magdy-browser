import Foundation

/// Builds the start page: speed-dial tiles from favorites and frequently visited sites.
/// Styling follows the Stitch design system (canvas #F5F5FB, 20pt white cards, indigo accents).
enum SpeedDialPage {

    struct Tile {
        let title: String
        let url: String
        let letter: String
        let color: String
    }

    static func tiles() -> [Tile] {
        var result: [Tile] = []
        var seen = Set<String>()

        // Folders are archives — only main-list favorites reach the speed dial.
        let mainList = FavoritesStore.shared.favorites(inFolder: nil)
        for favorite in mainList.prefix(8) {
            guard let host = URL(string: favorite.url)?.host, !seen.contains(host) else { continue }
            seen.insert(host)
            result.append(Tile(
                title: favorite.title.isEmpty ? host : favorite.title,
                url: favorite.url,
                letter: letter(for: host),
                color: color(for: host)
            ))
        }

        for top in HistoryStore.shared.topDomains(limit: 12) where result.count < 16 {
            guard !seen.contains(top.domain) else { continue }
            seen.insert(top.domain)
            result.append(Tile(
                title: top.title.isEmpty ? top.domain : top.title,
                url: "https://\(top.domain)",
                letter: letter(for: top.domain),
                color: color(for: top.domain)
            ))
        }
        return result
    }

    static func html() -> String {
        let tiles = tiles()
        let wallpaper = WallpaperStore.shared.materialiseSelection()
        let backgroundStyle: String
        if let wallpaper {
            backgroundStyle = """
            background-image:linear-gradient(180deg,var(--canvas-72) 0%,var(--canvas-92) 55%,var(--canvas-98) 100%),url('\(escape(wallpaper))');
            background-size:cover;background-position:center;
            """
        } else {
            backgroundStyle = "background:var(--canvas);"
        }

        let tileHTML = tiles.map { tile in
            let url = escape(tile.url)
            return """
            <a class="tile" href="\(url)">
              <span class="badge" style="background:\(tile.color)">\(escape(tile.letter))</span>
              <span class="label">\(escape(tile.title))</span>
              <span class="host">\(escape(URL(string: tile.url)?.host ?? tile.url))</span>
            </a>
            """
        }.joined(separator: "\n")

        let empty = tiles.isEmpty
            ? "<p class=\"empty\">Favorites and sites you visit will appear here as tiles.</p>"
            : ""

        // Greeting follows the device clock.
        let hour = Calendar.current.component(.hour, from: Date())
        let greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"

        let actions = [
            ("👁", "Private", "private"),
            ("⛶", "Scan QR", "qr"),
            ("🎙", "Voice", "voice"),
            ("⬇", "Downloads", "downloads")
        ].map { icon, label, action in
            """
            <button class="qa" onclick="webkit.messageHandlers.magdyAction.postMessage('\(action)')">
              <span class="qa-circle">\(icon)</span>
              <span class="qa-label">\(label)</span>
            </button>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
          :root{--canvas:#FAFAFC;--canvas-72:rgba(250,250,252,.72);--canvas-92:rgba(250,250,252,.92);
                --canvas-98:rgba(250,250,252,.98);--text:#1C1C1E;--muted:#8E8E93;
                --tile:#FFFFFF;--tile-shadow:0 2px 8px rgba(139,92,246,.05),0 8px 24px rgba(28,28,30,.07);
                --badge-shadow:0 6px 14px rgba(139,92,246,.28);
                --qa-bg:rgba(139,92,246,.12);--qa-border:rgba(139,92,246,.30)}
          @media (prefers-color-scheme:dark){
            :root{--canvas:#0D0E12;--canvas-72:rgba(13,14,18,.72);--canvas-92:rgba(13,14,18,.92);
                  --canvas-98:rgba(13,14,18,.98);--text:#F3F4F6;--muted:#9CA3AF;
                  --tile:#181920;--tile-shadow:0 2px 8px rgba(167,139,250,.06),0 8px 24px rgba(0,0,0,.35);
                  --badge-shadow:0 6px 14px rgba(0,0,0,.45);
                  --qa-bg:rgba(139,92,246,.15);--qa-border:rgba(139,92,246,.30)}
          }
          body{font-family:-apple-system,system-ui,sans-serif;margin:0;padding:20px 24px;
               color:var(--text);-webkit-font-smoothing:antialiased;min-height:100vh;
               \(backgroundStyle)}
          .topbar{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px}
          .protected{display:inline-flex;align-items:center;gap:6px;padding:5px 12px;border-radius:999px;
                     background:var(--qa-bg);border:1px solid var(--qa-border);color:#A78BFA;
                     font-size:12px;font-weight:600}
          h1{font-size:28px;font-weight:800;letter-spacing:-0.4px;margin:0 0 4px}
          p.note{color:var(--muted);font-size:14px;margin:0 0 18px}
          p.empty{color:var(--muted);font-size:14px;text-align:center;padding:40px 0}
          .qa-row{display:flex;justify-content:space-between;margin:0 2px 20px}
          .qa{background:none;border:0;padding:0;display:flex;flex-direction:column;align-items:center;gap:6px}
          .qa-circle{width:56px;height:56px;border-radius:999px;display:flex;align-items:center;justify-content:center;
                     background:var(--qa-bg);border:1px solid var(--qa-border);font-size:20px;color:#A78BFA}
          .qa-label{font-size:11px;color:var(--muted);font-weight:500}
          .grid{display:flex;flex-wrap:wrap;gap:14px}
          .tile{width:calc(33.333% - 10px);background:var(--tile);border-radius:16px;padding:16px 10px 14px;
                text-decoration:none;color:var(--text);display:flex;flex-direction:column;align-items:center;
                box-shadow:var(--tile-shadow)}
          .badge{width:48px;height:48px;border-radius:14px;color:#fff;font-weight:800;font-size:22px;
                 display:flex;align-items:center;justify-content:center;margin-bottom:10px;
                 box-shadow:var(--badge-shadow)}
          .label{font-size:13px;font-weight:700;text-align:center;
                 overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:100%}
          .host{font-size:11px;color:var(--muted);margin-top:2px;
                overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:100%}
        </style></head>
        <body>
          <div class="topbar"><span class="protected">🛡 Protected</span></div>
          <h1>\(greeting)</h1>
          <p class="note">\(escape(L.t("unlimited_note")))</p>
          <div class="qa-row">
          \(actions)
          </div>
          <div class="grid">
          \(tileHTML)
          </div>
          \(empty)
        </body></html>
        """
    }

    private static func letter(for host: String) -> String {
        String(host.prefix(1)).uppercased()
    }

    private static func color(for host: String) -> String {
        let palette = ["#8B5CF6", "#A78BFA", "#6C5CE7", "#0A84FF", "#30D158", "#FF9F0A", "#FF375F", "#64D2FF"]
        let hash = host.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
