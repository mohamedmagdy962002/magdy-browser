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
          :root{--canvas:#FBF8FF;--canvas-72:rgba(251,248,255,.72);--canvas-92:rgba(251,248,255,.92);
                --canvas-98:rgba(251,248,255,.98);--text:#1B1B21;--muted:#484553;
                --accent:#5F48BD;--accent-2:#7862D7;
                --tile:#FFFFFF;--tile-border:rgba(201,196,213,.55);
                --tile-shadow:0 2px 8px rgba(95,72,189,.05),0 8px 24px rgba(27,27,33,.06);
                --badge-shadow:0 6px 14px rgba(120,98,215,.30);
                --qa-bg:rgba(120,98,215,.10);--qa-border:rgba(201,196,213,.55)}
          @media (prefers-color-scheme:dark){
            :root{--canvas:#0D0E12;--canvas-72:rgba(13,14,18,.72);--canvas-92:rgba(13,14,18,.92);
                  --canvas-98:rgba(13,14,18,.98);--text:#F3F4F6;--muted:#9CA3AF;
                  --accent:#8B5CF6;--accent-2:#A78BFA;
                  --tile:#181920;--tile-border:rgba(38,39,52,.9);
                  --tile-shadow:0 2px 8px rgba(167,139,250,.06),0 8px 24px rgba(0,0,0,.35);
                  --badge-shadow:0 6px 14px rgba(0,0,0,.45);
                  --qa-bg:rgba(139,92,246,.15);--qa-border:rgba(139,92,246,.30)}
            .hero{background:rgba(24,25,32,.55);border-color:rgba(255,255,255,.12);
                  box-shadow:0 8px 32px rgba(0,0,0,.35)}
          }
          body{font-family:-apple-system,system-ui,sans-serif;margin:0;padding:20px 24px;
               color:var(--text);-webkit-font-smoothing:antialiased;min-height:100vh;
               \(backgroundStyle)}
          .topbar{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px}
          .protected{display:inline-flex;align-items:center;gap:6px;padding:5px 12px;border-radius:999px;
                     background:var(--qa-bg);border:1px solid var(--qa-border);color:var(--accent-2);
                     font-size:12px;font-weight:600}
          .hero{display:flex;flex-direction:column;align-items:center;gap:10px;
                padding:30px 20px 26px;text-align:center;border-radius:26px;margin:0 0 18px;
                background:rgba(255,255,255,.55);
                -webkit-backdrop-filter:blur(18px) saturate(1.4);backdrop-filter:blur(18px) saturate(1.4);
                border:1px solid rgba(255,255,255,.65);
                box-shadow:0 8px 32px rgba(95,72,189,.10)}
          .monogram{width:52px;height:52px;border-radius:16px;display:flex;align-items:center;justify-content:center;
                    background:linear-gradient(135deg,var(--accent-2),var(--accent));color:#fff;
                    font-size:26px;font-weight:800;box-shadow:var(--badge-shadow)}
          .wordmark{font-size:30px;font-weight:200;letter-spacing:.28em;margin-right:-.28em;
                    color:var(--text);text-transform:uppercase}
          .search-pill{display:flex;align-items:center;gap:8px;padding:10px 18px;border-radius:999px;
                       background:var(--tile);border:1px solid var(--tile-border);
                       box-shadow:var(--tile-shadow);color:var(--muted);font-size:14px}
          h1{font-size:28px;font-weight:800;letter-spacing:-0.4px;margin:0 0 4px}
          p.note{color:var(--muted);font-size:14px;margin:0 0 18px;text-align:center}
          p.empty{color:var(--muted);font-size:14px;text-align:center;padding:40px 0}
          .qa-row{display:flex;justify-content:space-between;margin:0 2px 20px}
          .qa{background:none;border:0;padding:0;display:flex;flex-direction:column;align-items:center;gap:6px}
          .qa-circle{width:56px;height:56px;border-radius:999px;display:flex;align-items:center;justify-content:center;
                     background:var(--qa-bg);border:1px solid var(--qa-border);font-size:20px;color:var(--accent-2)}
          .qa-label{font-size:11px;color:var(--muted);font-weight:500}
          .grid{display:flex;flex-wrap:wrap;gap:14px}
          .tile{width:calc(33.333% - 10px);background:var(--tile);border:1px solid var(--tile-border);
                border-radius:16px;padding:16px 10px 14px;
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
          <div class="hero">
            <span class="monogram">M</span>
            <span class="wordmark">Magdy</span>
            <span class="search-pill">🔍 Search</span>
          </div>
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
