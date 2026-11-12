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

        for favorite in FavoritesStore.shared.favorites.prefix(8) {
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
            background-image:linear-gradient(180deg,rgba(245,245,251,.72) 0%,rgba(245,245,251,.92) 55%,rgba(245,245,251,.98) 100%),url('\(escape(wallpaper))');
            background-size:cover;background-position:center;
            """
        } else {
            backgroundStyle = "background:#F5F5FB;"
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

        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
          body{font-family:-apple-system,system-ui,sans-serif;margin:0;padding:24px;
               color:#1C1C1E;-webkit-font-smoothing:antialiased;min-height:100vh;
               \(backgroundStyle)}
          h1{font-size:28px;font-weight:800;letter-spacing:-0.4px;margin:0 0 4px}
          p.note{color:#8E8E93;font-size:14px;margin:0 0 22px}
          p.empty{color:#8E8E93;font-size:14px;text-align:center;padding:40px 0}
          .grid{display:flex;flex-wrap:wrap;gap:16px}
          .tile{width:calc(33.333% - 11px);background:#fff;border-radius:20px;padding:16px 10px 14px;
                text-decoration:none;color:#1C1C1E;display:flex;flex-direction:column;align-items:center;
                box-shadow:0 2px 8px rgba(74,71,240,.04),0 8px 24px rgba(28,28,30,.06)}
          .badge{width:48px;height:48px;border-radius:14px;color:#fff;font-weight:800;font-size:22px;
                 display:flex;align-items:center;justify-content:center;margin-bottom:10px;
                 box-shadow:0 6px 14px rgba(74,71,240,.22)}
          .label{font-size:13px;font-weight:700;text-align:center;
                 overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:100%}
          .host{font-size:11px;color:#8E8E93;margin-top:2px;
                overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:100%}
        </style></head>
        <body>
          <h1>Magdy Browser</h1>
          <p class="note">\(escape(L.t("unlimited_note")))</p>
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
        let palette = ["#4A47F0", "#8A3FFC", "#0A84FF", "#30D158", "#FF9F0A", "#FF375F", "#64D2FF", "#BF5AF2"]
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
